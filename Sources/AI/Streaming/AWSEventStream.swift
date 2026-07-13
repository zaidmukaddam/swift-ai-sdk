import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AWSEventStreamMessage: Sendable, Hashable {
    public var headers: [String: String]
    public var payload: Data

    public init(headers: [String: String], payload: Data) {
        self.headers = headers
        self.payload = payload
    }
}

public enum AWSEventStreamError: Error, Sendable, CustomStringConvertible {
    case malformedFrame(String)
    case checksumMismatch(String)

    public var description: String {
        switch self {
        case .malformedFrame(let m): "Malformed event stream frame: \(m)"
        case .checksumMismatch(let m): "Event stream checksum mismatch: \(m)"
        }
    }
}

struct AWSEventStreamDecoder: Sendable {
    private var buffer: [UInt8] = []

    private static let minimumFrameLength = 16

    mutating func feed(_ byte: UInt8) throws -> AWSEventStreamMessage? {
        buffer.append(byte)
        guard buffer.count >= 4 else { return nil }
        let total = Int(Self.readUInt32(buffer, at: 0))
        guard total >= Self.minimumFrameLength else {
            throw AWSEventStreamError.malformedFrame(
                "declared length \(total) is below the 16-byte minimum"
            )
        }
        guard buffer.count >= total else { return nil }
        let frame = Array(buffer.prefix(total))
        buffer.removeFirst(total)
        return try Self.decode(frame)
    }

    mutating func feed(_ bytes: some Sequence<UInt8>) throws -> [AWSEventStreamMessage] {
        var messages: [AWSEventStreamMessage] = []
        for byte in bytes {
            if let message = try feed(byte) { messages.append(message) }
        }
        return messages
    }

    static func decode(_ frame: [UInt8]) throws -> AWSEventStreamMessage {
        guard frame.count >= minimumFrameLength else {
            throw AWSEventStreamError.malformedFrame(
                "frame is \(frame.count) bytes, minimum is \(minimumFrameLength)"
            )
        }
        let total = Int(readUInt32(frame, at: 0))
        guard total == frame.count else {
            throw AWSEventStreamError.malformedFrame(
                "declared length \(total) does not match frame size \(frame.count)"
            )
        }
        let headersLength = Int(readUInt32(frame, at: 4))
        guard headersLength <= total - minimumFrameLength else {
            throw AWSEventStreamError.malformedFrame(
                "headers length \(headersLength) exceeds frame capacity"
            )
        }

        let preludeCRC = readUInt32(frame, at: 8)
        let computedPrelude = CRC32.checksum(frame[0..<8])
        guard preludeCRC == computedPrelude else {
            throw AWSEventStreamError.checksumMismatch(
                "prelude CRC \(preludeCRC) != computed \(computedPrelude)"
            )
        }
        let messageCRC = readUInt32(frame, at: total - 4)
        let computedMessage = CRC32.checksum(frame[0..<(total - 4)])
        guard messageCRC == computedMessage else {
            throw AWSEventStreamError.checksumMismatch(
                "message CRC \(messageCRC) != computed \(computedMessage)"
            )
        }

        let headers = try decodeHeaders(frame[12..<(12 + headersLength)])
        let payload = Data(frame[(12 + headersLength)..<(total - 4)])
        return AWSEventStreamMessage(headers: headers, payload: payload)
    }

    private static func decodeHeaders(_ block: ArraySlice<UInt8>) throws -> [String: String] {
        var headers: [String: String] = [:]
        var cursor = block.startIndex

        func takeByte() throws -> UInt8 {
            guard cursor < block.endIndex else {
                throw AWSEventStreamError.malformedFrame("headers block truncated")
            }
            defer { cursor += 1 }
            return block[cursor]
        }
        func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard block.endIndex - cursor >= count else {
                throw AWSEventStreamError.malformedFrame("headers block truncated")
            }
            defer { cursor += count }
            return block[cursor..<(cursor + count)]
        }
        func takeUInt16() throws -> Int {
            let bytes = try take(2)
            return Int(bytes[bytes.startIndex]) << 8 | Int(bytes[bytes.startIndex + 1])
        }

        while cursor < block.endIndex {
            let nameLength = Int(try takeByte())
            let name = String(decoding: try take(nameLength), as: UTF8.self)
            switch try takeByte() {
            case 0: headers[name] = "true"
            case 1: headers[name] = "false"
            case 2: _ = try take(1)
            case 3: _ = try take(2)
            case 4: _ = try take(4)
            case 5: _ = try take(8)
            case 6: _ = try take(try takeUInt16())
            case 7: headers[name] = String(decoding: try take(try takeUInt16()), as: UTF8.self)
            case 8: _ = try take(8)
            case 9: _ = try take(16)
            case let tag:
                throw AWSEventStreamError.malformedFrame("unknown header value type \(tag)")
            }
        }
        return headers
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}

enum AWSEventStream {
    static func messages(
        from bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<AWSEventStreamMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = AWSEventStreamDecoder()
                do {
                    for try await byte in bytes {
                        if let message = try decoder.feed(byte) {
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0...255).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = ~0
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return ~crc
    }
}
