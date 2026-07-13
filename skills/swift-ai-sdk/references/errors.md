# Errors (AIError)

Every failure the SDK raises is an `AIError`. It is a `Sendable` enum conforming to `Error` and `CustomStringConvertible`, thrown from `try await generateText/streamText/generateObject/embed/...` and delivered to the optional `onError:` callback on the streaming paths. `import AI`.

## The type

```swift
public enum AIError: Error, Sendable, CustomStringConvertible {
    case http(status: Int, body: String)
    case decoding(String)
    case unknownTool(String)
    case invalidRequest(String)
    case transport(String)
    case noObjectGenerated(String)
}
```

`error.description` renders each case (`"HTTP 401: …"`, `"Decoding error: …"`, `"Unknown tool: …"`, `"Invalid request: …"`, `"Transport error: …"`, `"No object generated: …"`).

## When each is thrown

- `.http(status:body:)` — the provider returned a non-2xx status. `body` is the raw (streamed) response body. This is where auth failures (401), rate limits (429), quota, and server errors surface. A missing/empty API key typically lands here as 401.
- `.decoding(String)` — a provider response could not be parsed into the expected shape (malformed SSE / JSON, unexpected schema).
- `.unknownTool(String)` — a tool was referenced by a name the SDK cannot resolve at the tool layer (e.g. `Tool.execute` on a tool with no `run`). Note: during the model loop an unknown tool name usually becomes an **error `ToolResult`** rather than a thrown `AIError` (see below).
- `.invalidRequest(String)` — malformed input before/around the call: bad `provider:model` id or unregistered provider in `ProviderRegistry`, a provider that lacks the requested model kind, or an unsupported JSON Schema for on-device guided generation.
- `.transport(String)` — networking / framework-level failure with no HTTP status. Foundation Models maps most of its framework errors here (unavailable assets, PCC quota, generic `FoundationModels` `NSError`s).
- `.noObjectGenerated(String)` — `generateObject` completed but produced no parseable object matching the schema.

## do / catch

```swift
do {
    let result = try await generateText(model: model, prompt: "Hi")
    print(result.text)
} catch let error as AIError {
    switch error {
    case .http(let status, let body):
        print("provider \(status): \(body)")
    case .invalidRequest(let message):
        print("bad request: \(message)")
    case .noObjectGenerated(let message):
        print("no object: \(message)")
    default:
        print(error.description)
    }
} catch {
    print("other: \(error)")
}
```

## onError on the streaming path

`streamText` (and `generateText`, which share the loop) take an `onError: (@Sendable (Error) async -> Void)? = nil`. On the streaming path the error is passed to `onError` **and** re-thrown into the stream — iterating `fullStream` / `textStream` still throws it, so handle it in exactly one place:

```swift
let stream = streamText(
    model: model,
    prompt: "Hi",
    onError: { error in await report(error) }
)
do {
    for try await part in stream.fullStream {
        if case .textDelta(let t) = part { print(t, terminator: "") }
    }
} catch {
    // same error already delivered to onError above
}
```

Both `generateText` and `streamText` also take `maxRetries: Int = 2` — transient failures are retried before an error escapes.

## Tool errors become results, not throws

A tool that throws during execution does **not** abort the run. `executeToolCalls` catches it and feeds the model an error `ToolResult`:

- thrown error → `ToolResult(toolCallID:name:output: .string("Error: \(error)"), isError: true)`
- unknown tool name at loop time → `ToolResult(…, output: .string("Error: unknown tool '\(name)'"), isError: true)`

The model sees the error text and can recover on the next step. Inspect `result.toolResults` and check `.isError` to detect tool failures; they will not surface via `try`/`catch`.

## Gotchas

- Don't rely on typed HTTP subcases — 401/429/500 are all `.http(status:body:)`; branch on `status`.
- Tool-execution failures are silent to `try`/`catch`; find them in `result.toolResults` where `isError == true`.
- On the stream path an error reaches you twice (once via `onError`, once by re-throw from the stream) — pick one site to avoid double-reporting.
- Foundation Models guardrail/refusal is **not** an error: it ends the stream as `.finish(reason: .contentFilter, …)`. Check the finish reason, not `catch`.
- `AIError` is `CustomStringConvertible`; prefer `error.description` over `"\(error)"` for a stable message.
