import Foundation
@_exported import AI

public final class MockLanguageModel: LanguageModel, @unchecked Sendable {
    public let provider: String
    public let modelID: String

    private let handler: @Sendable (LanguageModelRequest, Int) async throws -> [StreamPart]
    private let chunkDelay: Duration?
    private let lock = NSLock()
    private var received: [LanguageModelRequest] = []

    public var requests: [LanguageModelRequest] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    public init(
        provider: String = "mock",
        modelID: String = "mock-model",
        chunkDelay: Duration? = nil,
        stream: @escaping @Sendable (LanguageModelRequest, Int) async throws -> [StreamPart]
    ) {
        self.provider = provider
        self.modelID = modelID
        self.chunkDelay = chunkDelay
        self.handler = stream
    }

    public convenience init(
        provider: String = "mock",
        modelID: String = "mock-model",
        chunkDelay: Duration? = nil,
        parts: [StreamPart]
    ) {
        self.init(provider: provider, modelID: modelID, chunkDelay: chunkDelay) { _, _ in parts }
    }

    public convenience init(
        provider: String = "mock",
        modelID: String = "mock-model",
        chunkDelay: Duration? = nil,
        responses: [[StreamPart]]
    ) {
        precondition(!responses.isEmpty, "MockLanguageModel needs at least one response")
        self.init(provider: provider, modelID: modelID, chunkDelay: chunkDelay) { _, call in
            responses[min(call, responses.count - 1)]
        }
    }

    public convenience init(
        provider: String = "mock",
        modelID: String = "mock-model",
        text: String,
        usage: Usage = Usage(inputTokens: 1, outputTokens: 1)
    ) {
        self.init(provider: provider, modelID: modelID, parts: [
            .textDelta(text), .finish(reason: .stop, usage: usage)
        ])
    }

    private func record(_ request: LanguageModelRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let call = received.count
        received.append(request)
        return call
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let call = record(request)
        let parts = try await handler(request, call)
        return simulateReadableStream(chunks: parts, chunkDelay: chunkDelay)
    }
}

public final class MockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let provider: String
    public let modelID: String

    private let vectors: [[Double]]
    private let lock = NSLock()
    private var received: [[String]] = []

    public var batches: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    public init(
        provider: String = "mock",
        modelID: String = "mock-embedding-model",
        vectors: [[Double]] = [[0.1, 0.2, 0.3]]
    ) {
        precondition(!vectors.isEmpty, "MockEmbeddingModel needs at least one vector")
        self.provider = provider
        self.modelID = modelID
        self.vectors = vectors
    }

    private func record(_ texts: [String]) {
        lock.lock()
        defer { lock.unlock() }
        received.append(texts)
    }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        record(texts)
        let embeddings = texts.indices.map { vectors[$0 % vectors.count] }
        return EmbeddingResponse(
            embeddings: embeddings,
            usage: Usage(inputTokens: texts.count, outputTokens: 0)
        )
    }
}

public func simulateReadableStream<Element: Sendable>(
    chunks: [Element],
    initialDelay: Duration? = nil,
    chunkDelay: Duration? = nil
) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                if let initialDelay { try await Task.sleep(for: initialDelay) }
                for chunk in chunks {
                    if let chunkDelay { try await Task.sleep(for: chunkDelay) }
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

public func mockValues<Value: Sendable>(_ values: Value...) -> @Sendable () -> Value {
    precondition(!values.isEmpty, "mockValues needs at least one value")
    let counter = MockCounter()
    return { values[min(counter.next(), values.count - 1)] }
}

private final class MockCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = count
        count += 1
        return value
    }
}
