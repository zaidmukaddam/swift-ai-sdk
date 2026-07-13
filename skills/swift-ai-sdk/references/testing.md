# Testing (AITesting)

`AITesting` is the `ai/test` analog: deterministic, network-free, key-free doubles that drive `generateText` / `streamText` / `generateObject` / `embed` in unit tests. A mock `LanguageModel` is just something that yields a scripted `[StreamPart]`. `import AITesting` (it `@_exported import AI`, so you get `AI` too).

## Package wiring

Add the product next to `AI` in the test target:

```swift
.testTarget(
  name: "MyAppTests",
  dependencies: [
    .product(name: "AI", package: "swift-ai-sdk"),
    .product(name: "AITesting", package: "swift-ai-sdk")
  ]
)
```

## MockLanguageModel

`public final class MockLanguageModel: LanguageModel`. It conforms to `LanguageModel` by recording each `LanguageModelRequest` and returning `simulateReadableStream(chunks:chunkDelay:)` over the parts its handler produces. Inits (all share `provider: String = "mock"`, `modelID: String = "mock-model"`, `chunkDelay: Duration? = nil`):

```swift
init(provider:modelID:chunkDelay:, stream: @Sendable (LanguageModelRequest, Int) async throws -> [StreamPart])
init(provider:modelID:chunkDelay:, parts: [StreamPart])
init(provider:modelID:chunkDelay:, responses: [[StreamPart]])
init(provider:modelID:, text: String, usage: Usage = Usage(inputTokens: 1, outputTokens: 1))
```

The `text:` one-liner covers most tests (it expands to `[.textDelta(text), .finish(reason: .stop, usage:)]`):

```swift
let model = MockLanguageModel(text: "Hello, world!")
let result = try await generateText(model: model, prompt: "Hi")
XCTAssertEqual(result.text, "Hello, world!")
```

Every request is recorded on `model.requests: [LanguageModelRequest]`, so you can assert on exactly what your code sent:

```swift
XCTAssertEqual(model.requests.count, 1)
XCTAssertEqual(model.requests[0].messages.last?.text, "Hi")
XCTAssertEqual(model.requests[0].reasoning, .medium)
```

## Scripting multi-step (tool) loops

`responses:` supplies one part-array per model round-trip; calls past the end replay the last script. That is enough to test a full tool loop end to end. `StreamPart` cases used here: `.toolCall(ToolCall)`, `.textDelta(String)`, `.finish(reason: FinishReason, usage: Usage)`. `ToolCall(id:name:arguments:)` where `arguments` is a `JSONValue`.

```swift
let model = MockLanguageModel(responses: [
  [
    .toolCall(ToolCall(id: "c1", name: "search", arguments: ["q": "swift"])),
    .finish(reason: .toolCalls, usage: .init())
  ],
  [
    .textDelta("Found it."),
    .finish(reason: .stop, usage: .init())
  ]
])

let result = try await generateText(model: model, prompt: "go", tools: [searchTool])
XCTAssertEqual(result.stepCount, 2)
XCTAssertEqual(result.text, "Found it.")
```

For full control, compute parts from the request and the zero-based call index:

```swift
let model = MockLanguageModel { request, callIndex in
  [.textDelta("call #\(callIndex)"), .finish(reason: .stop, usage: .init())]
}
```

Pass `chunkDelay: .milliseconds(n)` to pace parts like a live stream (drives `streamText` UI timing).

## MockEmbeddingModel

`public final class MockEmbeddingModel: EmbeddingModel`. `init(provider: "mock", modelID: "mock-embedding-model", vectors: [[Double]] = [[0.1, 0.2, 0.3]])`. Vectors cycle by input index (`vectors[i % count]`); `model.batches: [[String]]` records every input batch.

```swift
let model = MockEmbeddingModel(vectors: [[1, 0], [0, 1]])
let result = try await embedMany(model: model, values: ["a", "b", "c"])
XCTAssertEqual(model.batches.count, 1)
```

## Stream and value helpers

```swift
public func simulateReadableStream<Element: Sendable>(
  chunks: [Element], initialDelay: Duration? = nil, chunkDelay: Duration? = nil
) -> AsyncThrowingStream<Element, Error>

public func mockValues<Value: Sendable>(_ values: Value...) -> @Sendable () -> Value
```

`simulateReadableStream` turns any chunk array into a paced `AsyncThrowingStream`, so you can test a UI pipeline with no model at all. `mockValues` hands out values in order and sticks at the last — a deterministic id generator.

```swift
let stream = simulateReadableStream(
  chunks: uiMessageChunks, initialDelay: .milliseconds(100), chunkDelay: .milliseconds(10)
)
let nextID = mockValues("id-1", "id-2", "id-3")
```

## Testing chat UIs

Sessions take transports, and an `Agent` over a mock model is a transport, so a full `ChatSession` test needs no HTTP:

```swift
let agent = Agent(model: MockLanguageModel(text: "Hi there!"))
let chat = ChatSession(transport: agent)
chat.send("Hello")
```

Then await `chat.status == .ready` and assert on `chat.messages`.

## Gotchas

- The generic stream handler `init(stream:)` and its convenience overloads share default `provider`/`modelID`; if a call is ambiguous, label `parts:` / `responses:` / `text:` explicitly.
- `MockLanguageModel(responses:)` and `mockValues(...)` `precondition` a non-empty argument — an empty array crashes the test rather than failing softly.
- The model does not enforce a `.finish`; end each part-array with `.finish(reason:usage:)` or the loop may hang / never terminate the step.
- Tool execution happens in the SDK, not the mock — script the model's `.toolCall` and its follow-up text; the real tool's `execute` runs (or throws into an error `ToolResult`). Use the real tool or a stub tool, not the mock, to control tool output.
- `model.requests` is thread-safe (`NSLock`); read it after the awaited call returns.
- `StreamPart` (yielded by models) is distinct from `TextStreamPart` (from `streamText.fullStream`) — mocks yield `StreamPart`.
