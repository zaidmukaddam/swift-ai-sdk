import Foundation

public struct UIMessageStreamWriter: Sendable {
    private let continuation: AsyncThrowingStream<UIMessageChunk, Error>.Continuation
    private let merges: MergeTracker
    private let describeError: @Sendable (Error) -> String

    init(
        continuation: AsyncThrowingStream<UIMessageChunk, Error>.Continuation,
        merges: MergeTracker,
        describeError: @escaping @Sendable (Error) -> String
    ) {
        self.continuation = continuation
        self.merges = merges
        self.describeError = describeError
    }

    public func write(_ chunk: UIMessageChunk) {
        continuation.yield(chunk)
    }

    public func merge(_ chunks: AsyncThrowingStream<UIMessageChunk, Error>) {
        let continuation = self.continuation
        let describeError = self.describeError
        merges.track(Task {
            do {
                for try await chunk in chunks { continuation.yield(chunk) }
            } catch {
                continuation.yield(.error(errorText: describeError(error)))
            }
        })
    }
}

final class MergeTracker: Sendable {
    private let state = Mutex<[Task<Void, Never>]>([])

    func track(_ task: Task<Void, Never>) {
        state.withLock { $0.append(task) }
    }

    func waitForAll() async {
        while let task = state.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) {
            await task.value
        }
    }

    func cancelAll() {
        state.withLock { tasks in
            for task in tasks { task.cancel() }
            tasks.removeAll()
        }
    }
}

final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

public extension UIMessageStream {
    static func build(
        onError: @escaping @Sendable (Error) -> String = { "\($0)" },
        _ body: @escaping @Sendable (UIMessageStreamWriter) async throws -> Void
    ) -> AsyncThrowingStream<UIMessageChunk, Error> {
        AsyncThrowingStream { continuation in
            let merges = MergeTracker()
            let task = Task {
                let writer = UIMessageStreamWriter(
                    continuation: continuation, merges: merges, describeError: onError
                )
                do {
                    try await body(writer)
                } catch {
                    continuation.yield(.error(errorText: onError(error)))
                }
                await merges.waitForAll()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                merges.cancelAll()
            }
        }
    }
}

public func readUIMessageStream(
    _ chunks: AsyncThrowingStream<UIMessageChunk, Error>,
    message: UIMessage? = nil
) -> AsyncThrowingStream<UIMessage, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var reducer = message.map(UIMessageReducer.init(message:)) ?? UIMessageReducer()
            do {
                for try await chunk in chunks {
                    reducer.apply(chunk)
                    continuation.yield(reducer.message)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
