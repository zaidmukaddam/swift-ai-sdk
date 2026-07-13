# Chat UI

SwiftUI-facing `@Observable` sessions that stream a conversation, plus the transports that feed them. The wire format is byte-compatible with the AI SDK's `/api/chat` UI message stream, so an existing web chat route serves a Swift app unchanged. `import AI`.

All three sessions are `@Observable @MainActor final class`, available iOS 17 / macOS 14+. Keep one in `@State`.

## ChatSession

```swift
@Observable @MainActor public final class ChatSession {
    public enum Status: Sendable, Equatable { case ready, submitted, streaming, error(String) }

    public let id: String
    public private(set) var messages: [UIMessage]
    public private(set) var status: Status
    public var isLoading: Bool   // status == .submitted || .streaming

    public init(transport: any ChatTransport, id: String = UUID().uuidString, messages: [UIMessage] = [])

    public func send(_ text: String)                        // sugar for sendMessage(.user(text))
    public func sendMessage(_ message: UIMessage)
    public func regenerate()                                // drops last assistant msg, replays
    public func addToolResult(toolCallID: String, result: JSONValue)
    public func addToolApprovalResponse(approvalID: String, approved: Bool, reason: String? = nil)
    public func resumeStream()                              // reconnect contract, see below
    public func stop()                                      // cancels the in-flight task
    public func setMessages(_ newMessages: [UIMessage])     // stop() + replace, hydrate persisted history
}
```

`status` drives the spinner. `send`/`sendMessage`/`regenerate`/`setMessages`/`stop` all cancel any in-flight stream first. The assistant reply is reduced token-by-token via an internal `UIMessageReducer`; each applied chunk replaces the last element of `messages`.

`addToolResult` and `addToolApprovalResponse` mutate the matching `ToolUIPart` in place and automatically re-submit the conversation (`trigger: .submitMessage`) only once no tool part on that message is still pending (`.inputAvailable` for results, `.approvalRequested` for approvals). Do not manually re-send after calling them.

Minimal SwiftUI sketch:

```swift
struct ChatView: View {
    @State private var chat = ChatSession(
        transport: HTTPChatTransport(api: URL(string: "https://your-app.com/api/chat")!)
    )
    @State private var input = ""

    var body: some View {
        VStack {
            ScrollView {
                ForEach(chat.messages) { message in
                    ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                        switch part {
                        case .text(let t): Text(t.text)
                        case .reasoning(let r): Text(r.text).foregroundStyle(.secondary)
                        case .tool(let tool):
                            switch tool.state {
                            case .inputStreaming, .inputAvailable: ProgressView().id(tool.toolCallID)
                            case .approvalRequested:
                                Button("Approve") {
                                    if let id = tool.approval?.id {
                                        chat.addToolApprovalResponse(approvalID: id, approved: true)
                                    }
                                }
                            case .outputAvailable: Text(String(describing: tool.output))
                            default: EmptyView()
                            }
                        default: EmptyView()
                        }
                    }
                }
            }
            HStack {
                TextField("Message", text: $input)
                Button("Send") { chat.send(input); input = "" }.disabled(chat.isLoading)
            }
        }
    }
}
```

## CompletionSession

Single-turn text. `completion` accumulates deltas.

```swift
@Observable @MainActor public final class CompletionSession {
    public enum Status: Sendable, Equatable { case ready, loading, error(String) }
    public private(set) var completion: String
    public private(set) var status: Status
    public var isLoading: Bool

    public init(transport: any CompletionTransport)
    public init(model: any LanguageModel, system: String? = nil,
                maxOutputTokens: Int = 1024, temperature: Double? = nil)   // in-process

    public func complete(_ prompt: String)
    public func stop()
}
```

```swift
@State var completion = CompletionSession(transport: HTTPCompletionTransport(api: url))
completion.complete("Write a tagline for a coffee shop")
// read completion.completion as it grows
```

`HTTPCompletionTransport(api:headers:body:urlSession:)` POSTs `{ "prompt": ... }` (plus any `body` object keys) and reads `text-delta` chunks off the same UI message stream. So the local endpoint can be a normal chat route.

## ObjectSession

Streamed structured output. `object` is repaired partial JSON updated on every delta.

```swift
@Observable @MainActor public final class ObjectSession {
    public enum Status: Sendable, Equatable { case ready, loading, error(String) }
    public private(set) var object: JSONValue?
    public private(set) var status: Status
    public var isLoading: Bool

    public init(transport: any ObjectTransport)
    public init(model: any LanguageModel, schema: Schema, system: String? = nil,
                maxOutputTokens: Int = 1024, temperature: Double? = nil)   // in-process

    public func submit(_ input: JSONValue)          // JSONValue is ExpressibleByStringLiteral/-Dictionary
    public func decoded<T: Decodable>(_ type: T.Type = T.self) -> T?
    public func stop()
    public func clear()
}
```

```swift
@State var object = ObjectSession(transport: HTTPObjectTransport(api: url))
object.submit("Generate a recipe")               // string literal → JSONValue
let recipe: Recipe? = object.decoded()           // best-effort decode of the repaired partial
```

`HTTPObjectTransport(api:headers:urlSession:)` POSTs the raw `input` JSON and streams the response body as UTF-8 text fragments (not SSE) — the server writes a bare JSON object stream.

## Transports

```swift
public protocol ChatTransport: Sendable {
    func sendMessages(_ request: ChatRequest) async throws -> AsyncThrowingStream<UIMessageChunk, Error>
    func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<UIMessageChunk, Error>?  // default nil
}

public struct ChatRequest: Sendable {
    public var chatID: String
    public var messages: [UIMessage]
    public var trigger: ChatTrigger            // .submitMessage | .regenerateMessage
    public var messageID: String?
}
```

`HTTPChatTransport` — the usual choice, points at an AI SDK `/api/chat` POST route:

```swift
public struct HTTPChatTransport: ChatTransport {
    public init(api: URL, headers: [String: String] = [:],
                body: JSONValue? = nil, urlSession: URLSession = .shared)
}
```

POSTs `{ id, messages, trigger, messageId? }` (merging any `body` object keys), reads SSE frames terminated by `data: [DONE]`. `headers` carry auth. Implements the reconnect contract: `reconnectToStream` does `GET {api}/{chatId}/stream`, returning `nil` on HTTP 204 (nothing to resume). Wire `messages` as `messages.map(\.wire)`.

`LocalChatTransport` — in-process, no server; the usual way to run tools locally:

```swift
public struct LocalChatTransport: ChatTransport {
    public init(model: any LanguageModel, tools: [any AIToolProtocol] = [],
                system: String? = nil, maxOutputTokens: Int = 1024,
                temperature: Double? = nil, maxSteps: Int = 8)
}
let chat = ChatSession(transport: LocalChatTransport(model: FoundationModelsModel(), tools: [weather]))
```

`Agent` conforms to `ChatTransport` directly, so any configured agent is a transport:

```swift
let agent = Agent(model: AnthropicModel("claude-sonnet-5"), tools: [weather], maxSteps: 8)
let chat = ChatSession(transport: agent)
```

## UIMessage anatomy

```swift
public struct UIMessage: Sendable, Hashable, Identifiable {
    public var id: String
    public var role: UIRole            // system | user | assistant
    public var metadata: JSONValue?
    public var parts: [UIPart]
    public var text: String            // concatenated .text parts
    public static func user(_ text: String, id: String = UUID().uuidString) -> UIMessage
    public static func assistant(_ text: String, id: String = UUID().uuidString) -> UIMessage
}

public enum UIPart: Sendable, Hashable {
    case text(TextUIPart)              // .text, .state: streaming|done
    case reasoning(ReasoningUIPart)
    case tool(ToolUIPart)
    case sourceURL(SourceURLUIPart)
    case sourceDocument(SourceDocumentUIPart)
    case file(FileUIPart)              // .url (data: or remote), .mediaType, .filename
    case data(DataUIPart)              // custom server data parts, name after "data-"
    case stepStart
}
```

Tool part state machine (`ToolUIPart.state: UIToolState`): `inputStreaming` → `inputAvailable` → (`outputAvailable` | `outputError`), or the human-in-the-loop branch `approvalRequested` → `approvalResponded` → (`outputAvailable` | `outputDenied`). `toolName`, `toolCallID`, `input`, `output`, `errorText`, `approval: ToolApproval?`, `isDynamic`.

Build a message with attachments yourself rather than using `send`:

```swift
let msg = UIMessage(role: .user, parts: [
    .text(TextUIPart(text: "What's in this?")),
    .file(FileUIPart(url: "data:image/png;base64,...", mediaType: "image/png"))
])
chat.sendMessage(msg)
```

## Streaming protocol (serving + reading)

`UIMessageChunk` is the on-wire chunk enum. Serve from a Swift server (Vapor/Hummingbird/any SSE writer):

```swift
let result = streamText(model: model, messages: messages, tools: tools)
let chunks = UIMessageStream.chunks(from: result.fullStream)     // toUIMessageStreamResponse analog
response.headers = UIMessageStream.headers                       // includes x-vercel-ai-ui-message-stream: v1
for try await chunk in chunks {
    try await response.write(UIMessageStream.encodeSSE(chunk))   // "data: {json}\n\n"
}
try await response.write(UIMessageStream.doneSSE)                // "data: [DONE]\n\n"
```

Full signature:

```swift
static func UIMessageStream.chunks(
    from parts: AsyncThrowingStream<TextStreamPart, Error>,
    messageID: String? = nil,
    metadata: JSONValue? = nil,
    messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)? = nil
) -> AsyncThrowingStream<UIMessageChunk, Error>
```

Build arbitrary streams (the `createUIMessageStream` analog) and merge whole generation streams:

```swift
let stream = UIMessageStream.build { writer in
    writer.write(.data(name: "data-status", data: .string("searching")))
    let result = streamText(model: model, prompt: prompt)
    writer.merge(UIMessageStream.chunks(from: result.fullStream))
}
```

Consume any chunk stream to `UIMessage` snapshots without a session (persistence, server processing):

```swift
public func readUIMessageStream(_ chunks: AsyncThrowingStream<UIMessageChunk, Error>,
                                message: UIMessage? = nil) -> AsyncThrowingStream<UIMessage, Error>
```

`convertToModelMessages([UIMessage]) -> [Message]` turns client UI state into model history: data-URL file parts decode to inline bytes, settled tool calls carry their results, and `approvalResponded` parts become `toolApprovalResponse` entries for the loop to resolve.

## Gotchas

- **No `ChatSession(model:tools:)` convenience init.** For an in-process chat, wrap in a transport: `ChatSession(transport: LocalChatTransport(model:tools:))` or pass an `Agent` (which is itself a `ChatTransport`). `CompletionSession` and `ObjectSession` *do* have `model:` inits; `ChatSession` does not.
- **`messages`, `status`, `object`, `completion` are `private(set)`** — mutate only through the session methods.
- **`@MainActor`** — all session access must be on the main actor.
- **Re-submission is automatic** after `addToolResult`/`addToolApprovalResponse`, but only once the message has no remaining pending tool parts. Fill every pending part before it fires.
- **`resumeStream` requires the server side.** `HTTPChatTransport` implements `GET {api}/{chatId}/stream`; the default `ChatTransport.reconnectToStream` returns `nil`, so `LocalChatTransport`/`Agent` no-op it. Call it on foreground to pick up a response that kept generating.
- **`HTTPObjectTransport` is not SSE** — it reads a bare UTF-8 JSON object stream, unlike the chat/completion transports which parse `data:`-framed SSE ending in `[DONE]`.
- **Tool part wire `type`** is `tool-<name>` (or `dynamic-tool` when `isDynamic`), and data parts are `data-<name>`; the reducer strips those prefixes back into `toolName`/`name`.
- **`error` status carries a string** (`case error(String)`) from the transport or an in-band `error` chunk; there is no typed error.
