import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SSEEvent: Sendable {
    public var event: String
    public var data: String
}

struct SSEParser {
    private var event = ""
    private var dataLines: [String] = []

    mutating func feed(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            return flush()
        } else if line.hasPrefix(":") {
            return nil
        } else if line.hasPrefix("event:") {
            event = Self.value(of: line, after: "event:")
        } else if line.hasPrefix("data:") {
            dataLines.append(Self.value(of: line, after: "data:"))
        }
        return nil
    }

    mutating func flush() -> SSEEvent? {
        guard !dataLines.isEmpty else { event = ""; return nil }
        let completed = SSEEvent(event: event, data: dataLines.joined(separator: "\n"))
        event = ""
        dataLines.removeAll(keepingCapacity: true)
        return completed
    }

    private static func value(of line: String, after prefix: String) -> String {
        var value = String(line.dropFirst(prefix.count))
        if value.hasPrefix(" ") { value.removeFirst() }
        return value
    }
}

enum SSE {
    static func events(
        from bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var lineBuffer: [UInt8] = []

                func feedLine() {
                    if lineBuffer.last == 0x0D { lineBuffer.removeLast() }
                    let line = String(decoding: lineBuffer, as: UTF8.self)
                    lineBuffer.removeAll(keepingCapacity: true)
                    if let event = parser.feed(line) { continuation.yield(event) }
                }

                do {
                    for try await byte in bytes {
                        if byte == 0x0A {
                            feedLine()
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty { feedLine() }
                    if let event = parser.flush() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
