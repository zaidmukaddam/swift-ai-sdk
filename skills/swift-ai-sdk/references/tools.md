# Tools

Tools are anything conforming to `AIToolProtocol`: a name, description, JSON Schema `parameters`, and an async `execute`. `import AI`; pass tools to the top-level `generateText`/`streamText` via `tools:`.

## AIToolProtocol

```swift
public protocol AIToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: JSONValue { get }
    var hasExecutor: Bool { get }
    func needsApproval(_ arguments: JSONValue) async -> Bool
    func execute(_ arguments: JSONValue) async throws -> JSONValue
    func execute(_ arguments: JSONValue, options: ToolExecutionOptions) async throws -> JSONValue
}
```

`hasExecutor` defaults to `true`, `needsApproval` defaults to `false`, and the contextual `execute(_:options:)` defaults to forwarding to `execute(_:)`.

## Closure-based Tool

`Tool` is the concrete struct covering most cases. Four initializers: plain executor, executor plus `ToolExecutionOptions`, argument-dependent approval, and a no-executor form (client-side).

```swift
public init(
    name: String,
    description: String,
    parameters: JSONValue,
    needsApproval: Bool = false,
    execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
)

public init(
    name: String,
    description: String,
    parameters: JSONValue,
    needsApproval: Bool = false,
    execute: @escaping @Sendable (JSONValue, ToolExecutionOptions) async throws -> JSONValue
)

public init(
    name: String,
    description: String,
    parameters: JSONValue,
    needsApproval: @escaping @Sendable (JSONValue) async -> Bool,
    execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
)

public init(
    name: String,
    description: String,
    parameters: JSONValue
)
```

Build `parameters` with the `Schema` DSL (`Schema.object([...])`). `arguments` arrive as a `JSONValue`; read fields with accessors like `arguments["query"]?.stringValue`.

```swift
let search = Tool(
    name: "search",
    description: "Search the product catalog.",
    parameters: Schema.object(["query": .string()])
) { arguments in
    let query = arguments["query"]?.stringValue ?? ""
    return try await catalog.search(query)
}

let result = try await generateText(model: model, prompt: "Find running shoes", tools: [search])
```

## Tool.typed — Decodable arguments

Decodes the raw `JSONValue` into a `Decodable & Sendable` before your closure runs. A decode failure surfaces to the model as an error result rather than crashing.

```swift
public static func typed<Args: Decodable & Sendable>(
    name: String,
    description: String,
    parameters: JSONValue,
    argumentsType: Args.Type = Args.self,
    execute: @escaping @Sendable (Args) async throws -> JSONValue
) -> Tool
```

```swift
struct SearchArgs: Decodable { let query: String }

let search = Tool.typed(
    name: "search",
    description: "Search the product catalog.",
    parameters: Schema.object(["query": .string()])
) { (args: SearchArgs) in
    try await catalog.search(args.query)
}
```

## Execution context

The two-arg `execute` receives `ToolExecutionOptions`. `context` carries per-request data that never rides in the prompt; supply it through the `toolsContext:` parameter, keyed by tool name.

```swift
public struct ToolExecutionOptions: Sendable {
    public var toolCallID: String
    public var messages: [Message]
    public var context: JSONValue?
}
```

```swift
let orders = Tool(
    name: "list_orders",
    description: "List recent orders for the signed-in user.",
    parameters: Schema.object([:])
) { _, options in
    let userID = options.context?["userID"]?.stringValue ?? "anonymous"
    return try await store.orders(for: userID)
}

let result = try await generateText(
    model: model,
    prompt: "What did I order recently?",
    tools: [orders],
    toolsContext: ["list_orders": ["userID": .string("user-7")]]
)
```

`options.toolCallID` identifies the specific call; `options.messages` holds the step messages.

## Human-in-the-loop approvals

A tool that needs approval pauses the loop with a `ToolApprovalRequest` instead of executing. The app answers, and execution resumes on the next turn; a denial surfaces to the model as a denied `ToolResult` (`denied == true`).

```swift
public struct ToolApprovalRequest: Sendable, Hashable {
    public var approvalID: String
    public var call: ToolCall
}

public struct ToolApprovalResponse: Sendable, Hashable {
    public var approvalID: String
    public var toolCallID: String
    public var approved: Bool
    public var reason: String?
}
```

```swift
let delete = Tool(
    name: "delete_file",
    description: "Delete a file.",
    parameters: Schema.object(["path": .string()]),
    needsApproval: true
) { arguments in
    try await files.delete(arguments["path"]?.stringValue ?? "")
}
```

Argument-dependent approval uses the closure form: `needsApproval: { arguments in ... }`. In a chat UI, answer via `ChatSession`:

```swift
public func addToolApprovalResponse(approvalID: String, approved: Bool, reason: String? = nil)
```

When no approvals remain pending, the session resubmits automatically and the loop continues.

## Client-side tools (no executor)

A `Tool` built with the no-executor initializer has `hasExecutor == false`. The model emits the call, the loop ends the turn without executing it, and the app supplies the result whenever it is ready.

```swift
let pickPhoto = Tool(
    name: "pick_photo",
    description: "Ask the user to pick a photo.",
    parameters: Schema.object([:])
)

chat.addToolResult(toolCallID: toolCallID, result: ["photoID": "IMG_0042"])
```

`ChatSession.addToolResult(toolCallID:result:)` fills the pending call and resubmits once nothing is pending.

## Provider-executed tools

Providers run their own server-side tools (web/X search, code execution, file search, computer use) and stream the calls and results back in the same turn. Each provider exposes typed builders under `<Model>.Tools`; each returns a `ProviderDefinedTool`. Drop them into `tools:` alongside your own.

They carry no executor (`hasExecutor == false` on `ProviderDefinedTool`), so the loop never asks the app to run them and the turn does not pause. Calls and results arrive as `.toolCall` / `.toolResult` parts with `toolCall.providerExecuted == true`; web citations also surface as `.source`. Each provider ignores builders belonging to another provider (`providerToolEntries(for:)` filters by `provider`), so mixing across providers is safe.

### XaiModel.Tools (`provider: "xai"`)

```swift
static func webSearch(allowedDomains: [String]? = nil, excludedDomains: [String]? = nil, enableImageSearch: Bool? = nil, enableImageUnderstanding: Bool? = nil, name: String = "web_search") -> ProviderDefinedTool
static func xSearch(allowedXHandles: [String]? = nil, excludedXHandles: [String]? = nil, fromDate: String? = nil, toDate: String? = nil, enableImageUnderstanding: Bool? = nil, enableVideoUnderstanding: Bool? = nil, name: String = "x_search") -> ProviderDefinedTool
static func codeExecution(name: String = "code_interpreter") -> ProviderDefinedTool
static func fileSearch(vectorStoreIds: [String], maxNumResults: Int? = nil, name: String = "file_search") -> ProviderDefinedTool
static func mcpServer(serverUrl: String, serverLabel: String? = nil, serverDescription: String? = nil, allowedTools: [String]? = nil, headers: [String: String]? = nil, authorization: String? = nil, name: String = "mcp") -> ProviderDefinedTool
static func viewImage(name: String = "view_image") -> ProviderDefinedTool
static func viewXVideo(name: String = "view_x_video") -> ProviderDefinedTool
```

```swift
let result = try await generateText(
    model: XaiModel("grok-4.5"),
    prompt: "What shipped in AI this week?",
    tools: [
        XaiModel.Tools.webSearch(allowedDomains: ["arxiv.org"]),
        XaiModel.Tools.xSearch(allowedXHandles: ["xai"]),
    ]
)
```

### OpenAIModel.Tools (`provider: "openai"`)

```swift
static func webSearch(allowedDomains: [String]? = nil, externalWebAccess: Bool? = nil, searchContextSize: String? = nil, userLocation: JSONValue? = nil, name: String = "web_search") -> ProviderDefinedTool
static func webSearchPreview(searchContextSize: String? = nil, userLocation: JSONValue? = nil, name: String = "web_search_preview") -> ProviderDefinedTool
static func fileSearch(vectorStoreIds: [String], maxNumResults: Int? = nil, filters: JSONValue? = nil, name: String = "file_search") -> ProviderDefinedTool
static func codeInterpreter(fileIds: [String]? = nil, name: String = "code_interpreter") -> ProviderDefinedTool
static func computerUse(displayWidth: Int, displayHeight: Int, environment: String = "browser", name: String = "computer_use_preview") -> ProviderDefinedTool
```

### GroqModel.Tools (`provider: "groq"`)

```swift
static func browserSearch(name: String = "browser_search") -> ProviderDefinedTool
static func codeExecution(name: String = "code_execution") -> ProviderDefinedTool
```

For Groq's `groq/compound` models.

### GoogleModel.Tools (`provider: "google"`)

```swift
static func googleSearch(name: String = "google_search") -> ProviderDefinedTool
static func urlContext(name: String = "url_context") -> ProviderDefinedTool
static func codeExecution(name: String = "code_execution") -> ProviderDefinedTool
static func enterpriseWebSearch(name: String = "enterprise_web_search") -> ProviderDefinedTool
static func googleMaps(name: String = "google_maps") -> ProviderDefinedTool
static func fileSearch(fileSearchStoreNames: [String]? = nil, name: String = "file_search") -> ProviderDefinedTool
```

### AnthropicModel.Tools (`provider: "anthropic"`)

Each builder takes a dated `version:` string. The provider auto-injects the matching `anthropic-beta` header when the tool requires one (computer/bash/text-editor share `computer-use-*`, code execution uses `code-execution-*`, memory uses `context-management-*`, web fetch uses `web-fetch-*`); you do not set the header yourself.

```swift
static func webSearch(version: String = "web_search_20250305", maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, userLocation: JSONValue? = nil, name: String = "web_search") -> ProviderDefinedTool
static func webFetch(version: String = "web_fetch_20250910", maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, citations: JSONValue? = nil, maxContentTokens: Int? = nil, name: String = "web_fetch") -> ProviderDefinedTool
static func codeExecution(version: String = "code_execution_20250522", name: String = "code_execution") -> ProviderDefinedTool
static func bash(version: String = "bash_20250124", name: String = "bash") -> ProviderDefinedTool
static func textEditor(version: String = "text_editor_20250728", maxCharacters: Int? = nil) -> ProviderDefinedTool
static func computer(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil, version: String = "computer_20250124", name: String = "computer") -> ProviderDefinedTool
static func memory(version: String = "memory_20250818", name: String = "memory") -> ProviderDefinedTool
```

`textEditor` derives its wire name from the version (`str_replace_editor` for the 2024/early-2025 versions, `str_replace_based_edit_tool` otherwise) — do not override `name`.

### Raw escape hatch

For a server-side tool without a typed builder, construct one directly. `args` is the native tool entry the provider expects; `provider` must match the model's provider string.

```swift
public init(provider: String, id: String, name: String, args: JSONValue)
```

```swift
let custom = ProviderDefinedTool(
    provider: "openai",
    id: "openai.image_generation",
    name: "image_generation",
    args: .object(["type": .string("image_generation")])
)
```

## Validation

When `parameters` is built from the `Schema` DSL, arguments are validated before execution; malformed calls become error `ToolResult`s for the model to correct instead of crashing the tool.

## Computer use

Computer-use tools are **client-executed**. The model asks for an action; your code performs it and returns a screenshot. On OpenAI, `OpenAIModel.Tools.computerUse(displayWidth:displayHeight:)` surfaces each `computer_call` as a `computer_use_preview` tool call (`.arguments["action"]`); return the screenshot as `.image` content on the `ToolResult` and the library maps it to `computer_call_output`. On Anthropic, `AnthropicModel.Tools.computer(...)` / `bash()` / `textEditor()` run through the normal tool loop with the beta header set for you.

```swift
let call = result.toolCalls.first { $0.name == "computer_use_preview" }!
let png = try await perform(call.arguments["action"] ?? .object([:]))
messages.append(Message(role: .assistant, content: [.toolCall(call)]))
messages.append(Message(role: .tool, content: [.toolResult(ToolResult(
  toolCallID: call.id, name: call.name, output: .null,
  content: [.image(ImageContent(data: png, mediaType: "image/png"))]
))]))
```

## Multimodal tool results

Any tool can hand the model images, not just text. Set `Tool.modelOutput` to map the output to `[ContentPart]` (text + images); it populates `ToolResult.content`, which providers that support it (Anthropic image blocks, OpenAI computer output) send back. Providers without support fall back to the JSON `output`.

```swift
var shot = Tool(name: "screenshot", description: "…", parameters: schema) { _ in .object([:]) }
shot.modelOutput = { _ in [.text("Screen:"), .image(ImageContent(data: png, mediaType: "image/png"))] }
```

## Repairing tool calls

`repairToolCall` on `generateText`/`streamText` fires when a call names a tool that isn't in the set. Return a corrected `ToolCall`, or `nil` to skip.

```swift
repairToolCall: { call, tools in
  call.name == "web_serch" ? ToolCall(id: call.id, name: "web_search", arguments: call.arguments) : nil
}
```

## Gotchas

- `import AI`. `generateText`/`streamText` are top-level free functions, not methods on the model.
- The two-arg `execute(_:options:)` and one-arg `execute(_:)` are distinct initializers; only one runs. The one-arg default calls `execute` with an empty `ToolExecutionOptions(toolCallID: "")`, so `toolCallID`/`messages`/`context` are empty when a one-arg tool is invoked directly.
- `toolsContext` is keyed by tool name; a mismatched key leaves `options.context` nil.
- Calling `execute` on a `ProviderDefinedTool` throws `AIError.invalidRequest` — it is provider-run only. `hasExecutor` is `false`; the loop never invokes it.
- Provider-executed results are marked `providerExecuted == true`; do not treat them as pending client-side calls.
- Anthropic beta headers are added automatically per tool `id`; setting `anthropic-beta` manually is unnecessary and duplicates are de-duplicated.
- A no-executor `Tool` and a provider tool both end the turn without local execution, but for different reasons: the former waits for `addToolResult`, the latter is already resolved by the provider.
