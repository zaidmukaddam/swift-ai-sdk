# Agents

`Agent` is the `ToolLoopAgent` analog: a model bundled with instructions, tools, and loop settings, callable many times. `import AI`. Everything `generateText` accepts, `Agent` captures up front.

## Agent

```swift
public struct Agent: Sendable {
    public init(
        model: any LanguageModel,
        instructions: String? = nil,
        tools: [any AIToolProtocol] = [],
        toolChoice: ToolChoice = .auto,
        activeTools: [String]? = nil,
        toolOrder: [String]? = nil,
        toolsContext: [String: JSONValue] = [:],
        maxOutputTokens: Int = 1024,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        reasoning: ReasoningEffort = .providerDefault,
        stopWhen: [StopCondition]? = nil,
        maxSteps: Int = 8,
        prepareCall: PrepareCall? = nil,
        prepareStep: PrepareStep? = nil,
        onStepFinish: OnStepFinish? = nil,
        maxRetries: Int = 2,
        providerOptions: JSONValue? = nil
    )
}
```

`instructions` maps to the system prompt. All stored properties are public and `var`, so an agent can be copied and tweaked.

## Running

```swift
public func generate(prompt: String) async throws -> GenerateTextResult
public func generate(messages: [Message]) async throws -> GenerateTextResult
public func stream(prompt: String) -> StreamTextResult
public func stream(messages: [Message]) -> StreamTextResult
```

```swift
let agent = Agent(
    model: AnthropicModel("claude-sonnet-5"),
    instructions: "You are a terse weather assistant.",
    tools: [weatherTool],
    maxSteps: 6
)

let result = try await agent.generate(prompt: "Weather in Mumbai?")
let stream = agent.stream(messages: history)
```

Each method forwards straight to the top-level `generateText`/`streamText` with the agent's captured settings.

## Loop control

The loop runs up to `maxSteps` (default 8). `stopWhen` is an array of `StopCondition`; the loop stops when any condition is met after a step. Free functions and static factories exist for each.

```swift
public static func stepCountIs(_ count: Int) -> StopCondition      // steps.count >= count
public static func hasToolCall(_ toolNames: String...) -> StopCondition
public static func hasToolCall(_ toolNames: [String]) -> StopCondition
public static func isLoopFinished() -> StopCondition               // never true on its own
```

```swift
let agent = Agent(
    model: model,
    tools: [search],
    stopWhen: [stepCountIs(4), hasToolCall("final_answer")],
    maxSteps: 10
)
```

`stepCountIs(n)` matches when at least `n` steps have run. `hasToolCall(...)` matches when the last step called one of the named tools. `isLoopFinished()` is a no-op predicate (always `false`) used as an explicit "only the natural finish stops this" marker. `maxSteps` is the hard ceiling regardless of `stopWhen`.

## prepareCall — reconfigure the whole call

Runs once, before the loop, to reconfigure the entire call from runtime inputs. Return only the fields to change; a `nil` return (or `nil` field) falls through to the agent's values.

```swift
public struct PrepareCallContext: Sendable {
    public var messages: [Message]
    public var model: any LanguageModel
    public var tools: [any AIToolProtocol]
}

public struct PrepareCallResult: Sendable {
    public init(
        model: (any LanguageModel)? = nil,
        messages: [Message]? = nil,
        tools: [any AIToolProtocol]? = nil,
        toolChoice: ToolChoice? = nil,
        activeTools: [String]? = nil,
        toolOrder: [String]? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        reasoning: ReasoningEffort? = nil,
        providerOptions: JSONValue? = nil
    )
}

public typealias PrepareCall = @Sendable (PrepareCallContext) async throws -> PrepareCallResult?
```

```swift
let agent = Agent(
    model: OpenAIModel("gpt-5.6-luna"),
    tools: [search, calculator],
    prepareCall: { ctx in
        isHardQuestion(ctx.messages)
            ? PrepareCallResult(model: OpenAIModel("gpt-5.6-sol"), reasoning: .high)
            : nil
    }
)
```

## prepareStep — reconfigure per step

The step-level sibling of `prepareCall`; runs before each step and can swap the model, rewrite messages, or restrict tools for that step only.

```swift
public struct PrepareStepContext: Sendable {
    public var stepNumber: Int
    public var steps: [StepResult]
    public var messages: [Message]
    public var model: any LanguageModel
}

public struct PrepareStepResult: Sendable {
    public init(
        model: (any LanguageModel)? = nil,
        messages: [Message]? = nil,
        tools: [any AIToolProtocol]? = nil
    )
}

public typealias PrepareStep = @Sendable (PrepareStepContext) async throws -> PrepareStepResult?
```

## toolOrder

`toolOrder` fixes the order tools are sent to the provider — useful when a model is position-sensitive. Listed tools come first in the given order; anything unlisted is appended alphabetically.

```swift
Agent(model: model, tools: [search, calc, weather], toolOrder: ["weather", "search"])
// provider sees: weather, search, calc
```

## Subagents via asTool

Any agent becomes a `Tool` for another agent. The subagent runs its full loop and returns only its final text, keeping the orchestrator's context window clean.

```swift
public func asTool(
    name: String,
    description: String,
    promptDescription: String = "The task for the agent to perform."
) -> Tool
```

The generated tool takes a single required `prompt: String` argument, runs `generate(prompt:)`, and returns `result.text` as a `.string`.

```swift
let researcher = Agent(model: model, instructions: "You research questions and answer with dense facts.")
let writer = Agent(model: model, instructions: "You turn notes into friendly prose.")

let orchestrator = Agent(
    model: model,
    instructions: "Plan the work, delegate to specialists, then combine.",
    tools: [
        researcher.asTool(name: "researcher", description: "Delegate research."),
        writer.asTool(name: "writer", description: "Delegate drafting.")
    ]
)
```

## Agent as ChatTransport

`Agent` conforms to `ChatTransport`, so a chat UI can run against it in-process with no server.

```swift
@State var chat = ChatSession(transport: agent)
```

`sendMessages` converts UI messages to model messages, runs `stream(messages:)`, and emits `UIMessageChunk`s. On `.regenerateMessage` it truncates back to the target message (or drops the trailing assistant message) before rerunning. Regeneration, tool approvals, and client-side tool results all work identically to the HTTP transport.

## Gotchas

- `prepareCall`, `prepareStep`, `toolOrder`, `toolsContext`, `stopWhen`, and `onStepFinish` are also direct parameters on the top-level `generateText`/`streamText` — `Agent` is a convenience wrapper, not the only way to use them.
- `PrepareCallResult`/`PrepareStepResult` are additive overrides: omitted fields keep the agent's configured value. Returning `nil` changes nothing.
- `prepareCall` runs once for the whole call; `prepareStep` runs every step. Use `prepareCall` for model/tool selection up front, `prepareStep` for per-step narrowing.
- `stopWhen` conditions are evaluated after a step; `maxSteps` still caps the loop even if no condition ever matches. Default `maxSteps` is 8.
- `isLoopFinished()` never returns `true` by itself — it is a marker, not a real stop trigger; pair it with the natural finish reason.
- `hasToolCall` inspects only the last step's tool calls, not the whole history.
- `asTool` exposes exactly one string `prompt` parameter and returns only the subagent's final `text`; intermediate tool calls and reasoning stay inside the subagent.
- Default `maxOutputTokens` is 1024 — bump it for long completions.
