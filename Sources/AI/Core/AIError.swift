import Foundation

public enum AIError: Error, Sendable, CustomStringConvertible {
    case http(status: Int, body: String)
    case decoding(String)
    case unknownTool(String)
    case invalidRequest(String)
    case transport(String)
    case noObjectGenerated(String)

    public var description: String {
        switch self {
        case .http(let status, let body): "HTTP \(status): \(body)"
        case .decoding(let m): "Decoding error: \(m)"
        case .unknownTool(let name): "Unknown tool: \(name)"
        case .invalidRequest(let m): "Invalid request: \(m)"
        case .transport(let m): "Transport error: \(m)"
        case .noObjectGenerated(let m): "No object generated: \(m)"
        }
    }
}
