import Foundation

public struct AITelemetryEvent: Sendable {
    public enum Phase: String, Sendable {
        case start
        case end
        case error
    }

    public var name: String
    public var phase: Phase
    public var attributes: [String: JSONValue]
    public var duration: TimeInterval

    public init(
        name: String, phase: Phase,
        attributes: [String: JSONValue] = [:], duration: TimeInterval = 0
    ) {
        self.name = name
        self.phase = phase
        self.attributes = attributes
        self.duration = duration
    }
}

public protocol AITelemetryCollector: Sendable {
    func record(_ event: AITelemetryEvent)
}

public enum AITelemetry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _collector: (any AITelemetryCollector)?

    public static var collector: (any AITelemetryCollector)? {
        get { lock.withLock { _collector } }
        set { lock.withLock { _collector = newValue } }
    }

    static func record(_ event: AITelemetryEvent) {
        collector?.record(event)
    }

    static func span<T: Sendable>(
        _ name: String,
        attributes: [String: JSONValue] = [:],
        endAttributes: @Sendable (T) -> [String: JSONValue] = { _ in [:] },
        operation: () async throws -> T
    ) async rethrows -> T {
        guard collector != nil else { return try await operation() }
        let started = Date()
        record(AITelemetryEvent(name: name, phase: .start, attributes: attributes))
        do {
            let value = try await operation()
            record(AITelemetryEvent(
                name: name, phase: .end,
                attributes: attributes.merging(endAttributes(value)) { _, new in new },
                duration: Date().timeIntervalSince(started)
            ))
            return value
        } catch {
            record(AITelemetryEvent(
                name: name, phase: .error,
                attributes: attributes.merging(["error": .string("\(error)")]) { _, new in new },
                duration: Date().timeIntervalSince(started)
            ))
            throw error
        }
    }
}
