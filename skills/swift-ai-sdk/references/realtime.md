# Realtime voice

`RealtimeSession` is an `@Observable @MainActor` session for bidirectional live voice over WebSockets. Three providers speak their native wire behind one `RealtimeModel` protocol; the session normalizes everything to portable `RealtimeServerEvent`s and `UIMessage`s. `import AI`. iOS 17 / macOS 14+.

## Models

```swift
public struct OpenAIRealtimeModel: RealtimeModel {
    public init(_ modelID: String = "gpt-realtime", apiKey: String? = nil,   // env OPENAI_API_KEY
                baseURL: URL = .init(string: "https://api.openai.com/v1")!,
                headers: [String: String] = [:], urlSession: URLSession = .shared)
}
public struct GoogleRealtimeModel: RealtimeModel {          // Gemini Live
    public init(_ modelID: String, apiKey: String? = nil,   // env GOOGLE_GENERATIVE_AI_API_KEY
                baseURL: URL = .init(string: "https://generativelanguage.googleapis.com/v1beta")!,
                headers: [String: String] = [:], urlSession: URLSession = .shared)
}
public struct XaiRealtimeModel: RealtimeModel {             // Grok voice
    public init(_ modelID: String, apiKey: String? = nil,   // env XAI_API_KEY
                baseURL: URL = .init(string: "https://api.x.ai/v1")!,
                headers: [String: String] = [:], urlSession: URLSession = .shared)
}
```

All conform to:

```swift
public protocol RealtimeModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func createClientSecret(options: RealtimeClientSecretOptions) async throws -> RealtimeClientSecret
    func webSocketConfig(token: String, url: String) -> RealtimeWebSocketConfig
    func parseServerEvent(_ raw: JSONValue) -> [RealtimeServerEvent]
    func serializeClientEvent(_ event: RealtimeClientEvent) -> JSONValue?
    func buildSessionConfig(_ config: RealtimeSessionConfig) -> JSONValue
    func healthCheckResponse(for raw: JSONValue) -> JSONValue?   // default nil
}
```

## RealtimeSession

```swift
@Observable @MainActor public final class RealtimeSession {
    public enum Status: String, Sendable { case disconnected, connecting, connected, error }

    public private(set) var status: Status
    public private(set) var messages: [UIMessage]              // conversation, updated live
    public private(set) var events: [RealtimeServerEvent]      // capped at maxEvents

    public var onToolCall: (@Sendable (ToolCall) async throws -> JSONValue?)?
    public var onEvent: ((RealtimeServerEvent) -> Void)?
    public var onError: ((Error) -> Void)?
    public let audioOutput: AsyncStream<Data>                  // decoded PCM out

    public init(model: any RealtimeModel,
                sessionConfig: RealtimeSessionConfig = .init(),
                maxEvents: Int = 500,
                urlSession: URLSession = .shared,
                onToolCall: (@Sendable (ToolCall) async throws -> JSONValue?)? = nil)

    public func connect(secret: RealtimeClientSecret)
    public func connect(tokenEndpoint: URL, urlSession: URLSession = .shared) async throws
    public func disconnect()

    public func sendText(_ text: String)                       // creates item + requests response
    public func sendAudio(_ audio: Data)                       // base64-appends PCM to input buffer
    public func commitAudio()                                  // push-to-talk: end your turn
    public func clearAudioBuffer()
    public func requestResponse(modalities: [String]? = nil)
    public func cancelResponse()
    public func send(event: RealtimeClientEvent)               // escape hatch
    public func playbackInterrupted(playedMilliseconds: Int)   // barge-in / truncate
    public func addToolOutput(callID: String, output: JSONValue)
}
```

## Connecting

Realtime connections use short-lived client secrets. Mint on the server so the API key never ships:

```swift
// Server
let model = XaiRealtimeModel("grok-voice-latest")
let secret = try await model.createClientSecret(
    options: RealtimeClientSecretOptions(expiresAfterSeconds: 300, sessionConfig: config)
)
// return {token, url, expiresAt} to the app
```

App side, either pass the secret directly or let the session fetch and configure from a setup endpoint:

```swift
session.connect(secret: RealtimeClientSecret(token: token, url: url, expiresAt: expiresAt))

// or POST the session config to your endpoint, which returns {token, url, tools?}
try await session.connect(tokenEndpoint: URL(string: "https://your-app.com/api/realtime")!)
```

`connect(tokenEndpoint:)` POSTs `{ "sessionConfig": <native payload> }`, reads back `token`/`url`, and any `tools` array in the response is parsed into `RealtimeToolDefinition`s and merged into the session config automatically. On open, the session sends `sessionUpdate(config)`; `status` becomes `.connected` on the first `sessionCreated`/`sessionUpdated`.

## A voice session

```swift
let session = RealtimeSession(
    model: XaiRealtimeModel("grok-voice-latest"),
    sessionConfig: RealtimeSessionConfig(
        instructions: "You are a concise voice assistant.",
        inputAudioTranscription: .init(),
        turnDetection: .init(type: .serverVAD)
    ),
    onToolCall: { call in call.name == "getTime" ? .string(currentTime()) : nil }
)
session.connect(secret: secret)
session.sendText("Hello!")
```

`session.messages` renders as normal `UIMessage`s: streamed assistant transcripts, your speech transcribed and inserted at the point the audio was committed, and tool parts.

## Audio

The app owns capture and playback (real `AVAudioEngine`):

```swift
session.sendAudio(microphoneChunk)                    // 16-bit PCM in, 24 kHz default
for await chunk in session.audioOutput { player.play(chunk) }   // decoded PCM out
session.playbackInterrupted(playedMilliseconds: player.playedMilliseconds)   // barge-in
```

`sendAudio` base64-encodes and appends to the input buffer. `audioOutput` yields raw decoded `Data` (base64 `audioDelta` events decoded for you). `playbackInterrupted` truncates the current response item at the given ms so the model's context matches what the user actually heard.

## Session config

`RealtimeSessionConfig` is provider-neutral; each model maps it onto its native payload via `buildSessionConfig`.

```swift
RealtimeSessionConfig(
    instructions: "…",
    voice: "marin",
    outputModalities: ["audio"],                       // or ["text"]
    inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
    inputAudioTranscription: .init(model: nil, language: "en", prompt: nil),
    outputAudioTranscription: .init(),
    outputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
    turnDetection: .init(type: .serverVAD),
    tools: getRealtimeToolDefinitions(tools: [approve]),
    providerOptions: nil                               // merged into native payload
)
```

Audio format `type` is `audio/pcm` (with `rate`), `audio/pcmu`, or `audio/pcma`. Setting `inputAudioTranscription` is what makes your speech come back as `inputTranscriptionCompleted` events (inserted as user messages); `outputAudioTranscription` gives the model's spoken words as streaming text.

Turn detection:

```swift
public struct TurnDetection {
    public enum Kind: String { case serverVAD = "server-vad", semanticVAD = "semantic-vad", disabled }
    public init(type: Kind, threshold: Double? = nil,
                silenceDurationMs: Int? = nil, prefixPaddingMs: Int? = nil)
}
```

`.serverVAD` — server voice-activity detection ends turns on silence. `.semanticVAD` — ends on meaning where supported (xAI maps it to server VAD). `.disabled` — push-to-talk: stream `sendAudio` then call `commitAudio()` to end your turn yourself.

## Tools

Realtime tool execution is client-driven. Register definitions in the config, execute in `onToolCall`:

```swift
public func getRealtimeToolDefinitions(tools: [any AIToolProtocol]) -> [RealtimeToolDefinition]
```

Return a `JSONValue?` from `onToolCall` to answer immediately, or return `nil` and submit later:

```swift
session.addToolOutput(callID: call.id, output: .object(["approved": .bool(true)]))
```

On multi-tool turns the session requests exactly one follow-up response, and only after the turn closes (`responseDone`) and every registered call's output is in.

## Events

Normalized events arrive on `session.events` and through `onEvent`; every case carries the raw provider `JSONValue` for provider-specific handling.

```swift
public enum RealtimeServerEvent: Sendable {
    case sessionCreated(sessionID: String?, raw: JSONValue)
    case sessionUpdated(raw: JSONValue)
    case speechStarted(itemID: String?, raw: JSONValue)
    case speechStopped(itemID: String?, raw: JSONValue)
    case audioCommitted(itemID: String?, previousItemID: String?, raw: JSONValue)
    case conversationItemAdded(itemID: String, raw: JSONValue)
    case inputTranscriptionCompleted(itemID: String, transcript: String, raw: JSONValue)
    case responseCreated(responseID: String, raw: JSONValue)
    case responseDone(responseID: String, status: String, raw: JSONValue)
    case outputItemAdded/-Done(responseID:itemID:raw:)
    case contentPartAdded/-Done(responseID:itemID:raw:)
    case audioDelta(responseID:itemID:delta:raw:)      // base64 audio, what audioOutput decodes
    case audioDone(responseID:itemID:raw:)
    case audioTranscriptDelta/-Done(...)               // spoken response as text
    case textDelta/-Done(...)                          // text-modality output
    case functionCallArgumentsDelta/-Done(... name:arguments:raw:)
    case error(message: String, code: String?, raw: JSONValue)
    case custom(rawType: String, raw: JSONValue)       // anything with no portable shape
}
```

## Provider wire notes

- **OpenAI** connects with `realtime` + `openai-insecure-api-key.{token}` subprotocols; nests audio under `audio.input`/`audio.output`; input transcription defaults to `gpt-realtime-whisper` when enabled.
- **xAI** uses a single `xai-client-secret.{token}` subprotocol and a flat session shape.
- **Google (Gemini Live)** mints tokens against `v1alpha/auth_tokens` and connects with the token as `?access_token=` (no subprotocols). Its Live wire is stateful; the model maps `serverContent` frames onto the portable events and synthesizes response ids. Google **requires** the session config at token creation — that's why `RealtimeClientSecretOptions` carries `sessionConfig`.
- Keepalive frames are answered automatically via `healthCheckResponse(for:)`.

## Gotchas

- **`@MainActor`** — all session access on the main actor. Callbacks (`onToolCall`, `onEvent`, `onError`) are hopped to the main actor internally.
- **No API key on device for direct `connect(secret:)`** — mint the secret server-side. `createClientSecret` needs the key, so only call it on the server.
- **Google's config must be set before token creation**, not after connect — pass `sessionConfig` into `RealtimeClientSecretOptions`.
- **`.disabled` turn detection requires manual `commitAudio()`** after streaming, or the model never sees end-of-turn.
- **`onToolCall` returning `nil`** does *not* submit output — you must call `addToolOutput` later, otherwise the follow-up response never fires (the session waits for all registered calls).
- **`audioOutput` is a single `AsyncStream`** created at init; consume it once. It yields decoded PCM `Data`, not base64.
- **`events` is capped** at `maxEvents` (default 500, oldest dropped) — don't rely on it for full history; persist from `onEvent` if needed.
