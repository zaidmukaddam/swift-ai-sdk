import Foundation

enum Retry {
    static func withRetries<T: Sendable>(
        _ maxRetries: Int,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maxRetries, isRetryable(error) else { throw error }
                let delay = 0.5 * pow(2, Double(attempt)) * Double.random(in: 0.8...1.2)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let aiError = error as? AIError {
            switch aiError {
            case .http(let status, _):
                return status == 408 || status == 409 || status == 429 || (500..<600).contains(status)
            case .transport:
                return true
            default:
                return false
            }
        }
        return (error as? URLError) != nil
    }
}
