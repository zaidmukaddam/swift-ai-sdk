# Text generation

`generateText` and `streamText` are top-level functions in `import AI`. Both drive the same agentic loop: call the model, run any tools it requests, feed results back, repeat until the model answers or a stop condition is met. `generateText` returns the finished result; `streamText` yields events as they happen.

## generateText

```swift
public func generateText(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
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
    stopSequences: [String] = [],
    providerOptions: JSONValue? = nil,
    stopWhen: [StopCondition]? = nil,
    maxSteps: Int = 8,
    prepareCall: PrepareCall? = nil,
    prepareStep: PrepareStep? = nil,
    onStepFinish: OnStepFinish? = nil,
    onFinish: (@Sendable (GenerateTextResult) async -> Void)? = nil,
    onError: (@Sendable (Error) async -> Void)? = nil,
    repairToolCall: (@Sendable (ToolCall, [any AIToolProtocol]) async -> ToolCall?)? = nil,
    output: JSONValue? = nil,             // structured final object alongside tool calls → result.experimentalOutput
    maxRetries: Int = 2
) async throws -> GenerateTextResult
```

A minimal call. Provide either `prompt:` (a one-shot user turn) or `messages:` (full history), plus optionally `system:`.

```swift
import AI

let result = try await generateText(
    model: AnthropicModel("claude-sonnet-5"),
    system: "You are terse.",
    prompt: "Name three coastal cities."
)
print(result.text)
```

### GenerateTextResult

```swift
public struct GenerateTextResult: Sendable {
    public var text: String            // final assistant text (last step)
    public var reasoningText: String   // thinking from the last step, when exposed
    public var toolCalls: [ToolCall]   // every call across all steps
    public var toolResults: [ToolResult]
    public var sources: [Source]       // citations across all steps
    public var steps: [StepResult]     // one per model round-trip
    public var messages: [Message]     // full history incl. tool turns, ready to persist
    public var providerMetadata: JSONValue?   // per-provider extras, keyed by provider name
    public var experimentalOutput: JSONValue? // parsed object when `output:` was set
    public var finishReason: FinishReason
    public var usage: Usage            // combined across steps
    public var stepCount: Int { steps.count }
}
```

`text` and `reasoningText` reflect the last step only; `toolCalls`, `toolResults`, and `sources` are flattened across every step. `providerMetadata` collects structured extras merged by provider key: `["google"]["groundingMetadata"]`, `["openai"]["logprobs"]`, `["anthropic"]["cacheCreationInputTokens"]`, `["bedrock"]["trace"]`, `["perplexity"]["images"/"related_questions"]`.

## streamText

```swift
public func streamText(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
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
    stopSequences: [String] = [],
    providerOptions: JSONValue? = nil,
    stopWhen: [StopCondition]? = nil,
    maxSteps: Int = 8,
    prepareCall: PrepareCall? = nil,
    prepareStep: PrepareStep? = nil,
    onStepFinish: OnStepFinish? = nil,
    onFinish: (@Sendable (GenerateTextResult) async -> Void)? = nil,
    onError: (@Sendable (Error) async -> Void)? = nil,
    onChunk: (@Sendable (TextStreamPart) -> Void)? = nil,   // fires per streamed part
    onAbort: (@Sendable () async -> Void)? = nil,           // fires on cancellation
    repairToolCall: (@Sendable (ToolCall, [any AIToolProtocol]) async -> ToolCall?)? = nil,
    maxRetries: Int = 2
) -> StreamTextResult
```

`streamText` is not `async`/`throws`; it returns immediately. Nothing runs until you iterate a stream, and dropping the stream cancels the underlying work.

```swift
public struct StreamTextResult: Sendable {
    public let fullStream: AsyncThrowingStream<TextStreamPart, Error>
    public var textStream: AsyncThrowingStream<String, Error> { get }
    // smoothedTextStream(chunking: .word/.line, delay:) re-chunks textStream for calmer UI
}
```

`fullStream` also emits `.providerMetadata(JSONValue)`. Wrap `textStream` with the top-level `smoothStream(_:chunking:delay:)` (or `result.smoothedTextStream()`) to re-chunk deltas by word or line with an optional delay.

`textStream` is `fullStream` reduced to assistant `.textDelta` values only.

### .textStream — assistant text only

```swift
let result = streamText(model: model, prompt: "Write a haiku about fog.")
for try await delta in result.textStream {
    print(delta, terminator: "")
}
```

### .fullStream — every event

`fullStream` yields `TextStreamPart`:

```swift
public enum TextStreamPart: Sendable {
    case startStep(index: Int)                                // round-trip begins (0-based)
    case textDelta(String)                                    // assistant text, token by token
    case reasoningDelta(String)                               // thinking text, when streamed
    case toolInputStart(id: String, name: String)            // a tool call began; args still streaming
    case toolInputDelta(id: String, partialJSON: String)     // fragment of the call's JSON args
    case toolCall(ToolCall)                                   // args fully assembled; about to run
    case toolResult(ToolResult)                               // a tool finished; output goes back to model
    case toolApprovalRequest(ToolApprovalRequest)            // call held for user; turn ends after this
    case source(Source)                                       // citation from search-backed providers
    case finishStep(StepResult)                              // round-trip closed
    case finish(finishReason: FinishReason, totalUsage: Usage) // terminal event for the whole loop
}
```

The `toolInputStart` / `toolInputDelta` pair is what lets a UI render a tool card filling in while the model is still writing arguments.

```swift
let result = streamText(model: model, prompt: prompt, tools: [weather])
for try await part in result.fullStream {
    switch part {
    case .textDelta(let delta):          render(delta)
    case .reasoningDelta(let delta):     renderThinking(delta)
    case .toolCall(let call):            showToolChip(call)
    case .toolResult(let toolResult):    updateToolChip(toolResult)
    case .finishStep(let step):          persist(step)
    case .finish(let reason, let usage): log(reason, usage)
    default:                             break
    }
}
```

## Building the prompt: system/prompt vs messages

Two mutually compatible ways to supply input. Internally they are assembled in this order: `system` (if any) prepended as a `.system` message, then `messages`, then `prompt` (if any) appended as a `.user` message.

```swift
let a = try await generateText(model: model, system: "Be brief.", prompt: "Hi")

let b = try await generateText(model: model, messages: [
    .system("Be brief."),
    .user("What's in this image?"),
    .assistant("A lighthouse."),
    .user("At what time of day?")
])
```

### Message and Role

```swift
public struct Message: Sendable, Hashable {
    public var role: Role
    public var content: [ContentPart]
    public init(role: Role, content: [ContentPart])

    public static func system(_ text: String) -> Message
    public static func user(_ text: String) -> Message
    public static func assistant(_ text: String) -> Message
    public static func user(_ text: String, images: [ImageContent]) -> Message

    public var text: String   // concatenation of all .text parts
}

public enum Role: String, Sendable, Codable, Hashable {
    case system, user, assistant, tool
}
```

The loop manages `.tool` turns for you; write them only when replaying persisted history.

### ContentPart

```swift
public enum ContentPart: Sendable, Hashable {
    case text(String)
    case image(ImageContent)
    case file(FileContent)
    case toolCall(ToolCall)                        // in assistant messages
    case toolResult(ToolResult)                    // in tool messages
    case toolApprovalResponse(ToolApprovalResponse)
}
```

`ImageContent` and `FileContent` each take inline `data` or a remote `url`:

```swift
public struct ImageContent: Sendable, Hashable {
    public init(data: Data, mediaType: String? = nil)
    public init(url: URL, mediaType: String? = nil)
}

public struct FileContent: Sendable, Hashable {
    public init(data: Data, mediaType: String, filename: String? = nil)
    public init(url: URL, mediaType: String, filename: String? = nil)
}
```

Multimodal input rides as content parts and maps to each provider's native shape:

```swift
let result = try await generateText(
    model: GoogleModel("gemini-3.5-flash"),
    messages: [Message(role: .user, content: [
        .text("Summarize this report."),
        .file(FileContent(data: pdfData, mediaType: "application/pdf", filename: "q3.pdf"))
    ])]
)
```

### ToolCall / ToolResult

```swift
public struct ToolCall: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
    public var providerExecuted: Bool
}

public struct ToolResult: Sendable, Hashable {
    public var toolCallID: String
    public var name: String
    public var output: JSONValue
    public var isError: Bool
    public var denied: Bool
}
```

## Sampling settings

Every knob maps to the provider's native field and is dropped where a wire lacks it: `maxOutputTokens` (default 1024), `temperature`, `topP`, `topK`, `presencePenalty`, `frequencyPenalty`, `seed`, `stopSequences`. All except `maxOutputTokens` and `stopSequences` are optional and default to nil/empty.

```swift
let result = try await generateText(
    model: model,
    prompt: prompt,
    maxOutputTokens: 2048,
    temperature: 0.2,
    topP: 0.9,
    seed: 42,
    stopSequences: ["\n\nUser:"]
)
```

## Steering the loop: maxSteps and stopWhen

The loop runs multiple round-trips whenever the model calls tools. `maxSteps` (default 8) bounds it when no `stopWhen` is given; `stopWhen` takes an array of `StopCondition` and the first met condition ends the loop.

```swift
public struct StopCondition: Sendable {
    public init(_ predicate: @escaping @Sendable ([StepResult]) -> Bool)
    public static func stepCountIs(_ count: Int) -> StopCondition   // alias: isStepCount
    public static func isLoopFinished() -> StopCondition
    public static func hasToolCall(_ toolNames: String...) -> StopCondition
    public static func hasToolCall(_ toolNames: [String]) -> StopCondition
}
```

Free-function forms exist too: `stepCountIs(_:)`, `isStepCount(_:)`, `isLoopFinished()`, `hasToolCall(_:)`.

```swift
let result = try await generateText(
    model: model,
    prompt: prompt,
    tools: tools,
    toolChoice: .required,
    activeTools: ["search"],
    stopWhen: [.stepCountIs(5), .hasToolCall("finalize")]
)
```

`toolChoice` is `.auto`, `.none`, `.required`, or `.tool("name")`. `activeTools` restricts which registered tools are visible on a step without unregistering their executors.

### StepResult

Each round-trip lands in `result.steps`:

```swift
public struct StepResult: Sendable {
    public var text: String
    public var reasoningText: String
    public var toolCalls: [ToolCall]
    public var toolResults: [ToolResult]
    public var sources: [Source]
    public var approvalRequests: [ToolApprovalRequest]
    public var finishReason: FinishReason
    public var usage: Usage
}
```

### FinishReason and Usage

```swift
public enum FinishReason: String, Sendable, Codable, Hashable {
    case stop, length, toolCalls, contentFilter, error, other
}

public struct Usage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedInputTokens: Int?   // prompt-cache hits, where reported
    public var reasoningTokens: Int?     // thinking tokens, where reported
    public var totalTokens: Int { inputTokens + outputTokens }
}
```

## Lifecycle callbacks

- `onStepFinish: @Sendable (StepResult) async -> Void` — fires after each round-trip (before the loop decides whether to continue).
- `onFinish: @Sendable (GenerateTextResult) async -> Void` — fires once with the final result. On `streamText` it fires after the stream completes successfully.
- `onError: @Sendable (Error) async -> Void` — fires on a thrown error, then the error propagates (rethrown by `generateText`, or finishes the stream with the error).

```swift
let result = try await generateText(
    model: model,
    prompt: prompt,
    tools: tools,
    onStepFinish: { step in await save(step) },
    onFinish: { final in await log(final.usage) },
    onError: { error in await report(error) }
)
```

## Sources and citations

Search-backed providers surface citations as `Source`:

```swift
public struct Source: Sendable, Hashable {
    public var id: String
    public var url: String
    public var title: String?
}
```

Read them from `result.sources` (or `step.sources`) after `generateText`, or observe them live on the stream via `.source(Source)`.

```swift
let result = try await generateText(model: model, prompt: "Latest on X, with citations.")
for source in result.sources {
    print(source.title ?? source.url, source.url)
}
```

## Gotchas

- `streamText` is synchronous and lazy — no work runs until you iterate `fullStream` or `textStream`. Consume exactly one of the two per call; each drives the loop, and iterating both double-drives it.
- Dropping/cancelling the stream cancels the in-flight generation (`onTermination` cancels the backing task).
- `result.text` / `result.reasoningText` come from the last step only. To see intermediate assistant text across tool round-trips, walk `result.steps`.
- `finishReason` is `.toolCalls` (not `.stop`) when the loop stops because a stop condition was met while tools were still being requested, or when client-side/approval-gated calls end the turn.
- `reasoning:` is a non-optional enum defaulting to `.providerDefault`; `.none` explicitly disables thinking (see reasoning.md).
- `providerOptions` merges into the request body last and wins over anything the library sets, including `reasoning`.
- Provide `prompt:` or `messages:` (or both). If you pass neither and no `system`, the model receives an empty conversation.
