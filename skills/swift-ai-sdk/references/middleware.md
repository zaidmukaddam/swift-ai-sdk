# Middleware

Middleware intercepts a model's requests and stream parts. `wrapLanguageModel` returns a new `any LanguageModel` that applies a stack of `LanguageModelMiddleware` around the base model. `import AI`.

## wrapLanguageModel

```swift
public func wrapLanguageModel(
    model: any LanguageModel,
    middleware: [LanguageModelMiddleware]
) -> any LanguageModel
```

```swift
let model = wrapLanguageModel(
    model: OllamaModel("qwen3"),
    middleware: [
        .cache(),
        .extractReasoning(tag: "think"),
        .defaultSettings(temperature: 0.2)
    ]
)
```

The wrapped model forwards `provider`/`modelID` from the base and is a drop-in replacement everywhere a `LanguageModel` is accepted.

## Built-ins

```swift
static func extractReasoning(tag: String = "think") -> LanguageModelMiddleware
static func simulateStreaming() -> LanguageModelMiddleware
static func defaultSettings(temperature: Double? = nil, topP: Double? = nil, maxOutputTokens: Int? = nil, providerOptions: JSONValue? = nil) -> LanguageModelMiddleware
static func cache(store: any LanguageModelCache = InMemoryLanguageModelCache()) -> LanguageModelMiddleware
```

- `extractReasoning(tag:)` — a `wrapStream` hook that lifts `<tag>...</tag>` spans out of text deltas and re-emits them as `.reasoningDelta`. Handles tags split across delta boundaries.
- `simulateStreaming()` — a `wrapStream` hook that buffers the entire inner stream, then replays it with adjacent text/reasoning deltas coalesced. Turns a non-streaming endpoint into a streaming one.
- `defaultSettings(...)` — a `transformRequest` hook that fills in values only when unset: `temperature`/`topP` when `nil`, `maxOutputTokens` only when it still equals the library default (1024), and deep-merges `providerOptions` as defaults under any request-supplied overrides.
- `cache(store:)` — a `wrapCall` hook; see below.

## Caching

`cache()` keys on the request plus the wrapped model's identity. A hit replays the stored stream parts without calling the model; a miss streams live, buffers the parts, and stores them once the stream completes. Errors are never cached (a throwing stream finishes without a `set`).

```swift
let store = InMemoryLanguageModelCache()
let model = wrapLanguageModel(model: OpenAIModel("gpt-5.6-luna"), middleware: [.cache(store: store)])
```

The cache key is a sorted-keys JSON encoding of: provider, model id, messages, `maxOutputTokens`, reasoning, tool choice, response format, plus tools (name/description/parameters) and any set sampling params, stop sequences, and provider options. Any difference in these produces a distinct key.

### LanguageModelCache

```swift
public protocol LanguageModelCache: Sendable {
    func get(_ key: String) async -> [StreamPart]?
    func set(_ key: String, _ value: [StreamPart]) async
}
```

Conform to back the cache with Redis, disk, or anything else. The default `InMemoryLanguageModelCache` is a process-local actor:

```swift
public actor InMemoryLanguageModelCache: LanguageModelCache {
    public init()
    public func get(_ key: String) -> [StreamPart]?
    public func set(_ key: String, _ value: [StreamPart])
    public func removeAll()
}
```

## Hook types

A `LanguageModelMiddleware` is a value with any combination of three optional hooks:

```swift
public struct LanguageModelMiddleware: Sendable {
    public init(
        transformRequest: (@Sendable (LanguageModelRequest) async throws -> LanguageModelRequest)? = nil,
        wrapCall: (@Sendable (MiddlewareCallContext, MiddlewareNext) async throws -> AsyncThrowingStream<StreamPart, Error>)? = nil,
        wrapStream: (@Sendable (AsyncThrowingStream<StreamPart, Error>) -> AsyncThrowingStream<StreamPart, Error>)? = nil
    )
}

public typealias MiddlewareNext = @Sendable (LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error>

public struct MiddlewareCallContext: Sendable {
    public var request: LanguageModelRequest
    public var provider: String
    public var modelID: String
}
```

- `transformRequest` — edit the request before it goes out. Runs first, in array order, across all middleware.
- `wrapStream` — post-process the stream of `StreamPart`s the model returns.
- `wrapCall` — wrap the whole call and decide whether to invoke the model at all (it receives `next`, the continuation into the inner call). This is what `cache()` uses: on a hit it returns a synthetic stream and never calls `next`.

```swift
let logger = LanguageModelMiddleware(
    transformRequest: { request in
        print("sending \(request.messages.count) messages")
        return request
    }
)
```

## Ordering

Middlewares apply in array order. Concretely, in `wrapLanguageModel(model:middleware:)`:

- `transformRequest` runs front-to-back, so earlier entries see the request first.
- `wrapCall` and `wrapStream` are composed in reverse, so the first entry in the array is the outermost wrapper (it sees the request last on the way in and the parts first on the way out).

```swift
wrapLanguageModel(model: base, middleware: [.cache(), .extractReasoning()])
```

Here `cache` is outermost: a cache hit short-circuits before `extractReasoning` ever runs; a miss lets the live stream pass through `extractReasoning`, and the reasoning-extracted parts are what get cached.

## Gotchas

- `wrapCall` owns the decision to call the model; it can synthesize a stream and skip `next` entirely (the caching pattern). `transformRequest`/`wrapStream` always pass through to the model.
- Array order matters and is asymmetric: `transformRequest` is front-to-back, but `wrapCall`/`wrapStream` wrap in reverse so index 0 is outermost. Put short-circuiting middleware (like `cache`) first to have it wrap everything else.
- `cache()` never stores errored streams, so a failed call is retried live next time.
- `defaultSettings(maxOutputTokens:)` only applies when the request still holds the library default (1024); an explicitly set value is left untouched.
- The cache key includes tool definitions and provider options — changing a tool's schema or provider options is a cache miss, which is usually what you want.
- `wrapStream` is synchronous (`-> AsyncThrowingStream`, not `async`); do async work inside a `Task` in the returned stream, as the built-ins do.
