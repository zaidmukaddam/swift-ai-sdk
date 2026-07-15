import Foundation

public enum SmoothStreamChunking: Sendable {
    case word
    case line
}

public func smoothStream(
    _ input: AsyncThrowingStream<String, Error>,
    chunking: SmoothStreamChunking = .word,
    delay: Duration? = .milliseconds(10)
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var buffer = ""
            do {
                for try await delta in input {
                    buffer += delta
                    while let chunk = nextSmoothChunk(&buffer, chunking) {
                        continuation.yield(chunk)
                        if let delay { try await Task.sleep(for: delay) }
                    }
                }
                if !buffer.isEmpty { continuation.yield(buffer) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

public extension StreamTextResult {
    func smoothedTextStream(
        chunking: SmoothStreamChunking = .word,
        delay: Duration? = .milliseconds(10)
    ) -> AsyncThrowingStream<String, Error> {
        smoothStream(textStream, chunking: chunking, delay: delay)
    }
}

private func nextSmoothChunk(_ buffer: inout String, _ chunking: SmoothStreamChunking) -> String? {
    switch chunking {
    case .line:
        guard let newline = buffer.firstIndex(of: "\n") else { return nil }
        let end = buffer.index(after: newline)
        let chunk = String(buffer[..<end])
        buffer.removeSubrange(..<end)
        return chunk
    case .word:
        var sawNonSpace = false
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            if character.isWhitespace {
                if sawNonSpace {
                    var end = index
                    while end < buffer.endIndex, buffer[end].isWhitespace {
                        end = buffer.index(after: end)
                    }
                    let chunk = String(buffer[..<end])
                    buffer.removeSubrange(..<end)
                    return chunk
                }
            } else {
                sawNonSpace = true
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}
