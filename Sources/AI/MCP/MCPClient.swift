import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol MCPTransport: Sendable {
    func request(id: Int, method: String, params: JSONValue) async throws -> JSONValue
    func notify(method: String) async throws
    func close() async
}

public extension MCPTransport {
    func close() async {}
}

public actor MCPClient {
    public let transport: any MCPTransport
    private var initialized = false
    private var nextID = 1

    public init(transport: any MCPTransport) {
        self.transport = transport
    }

    public func close() async {
        await transport.close()
    }

    public func connect(
        clientName: String = "swift-ai-sdk", clientVersion: String = "0.2.0"
    ) async throws {
        guard !initialized else { return }
        _ = try await request(method: "initialize", params: .object([
            "protocolVersion": "2025-06-18",
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string(clientVersion)
            ])
        ]))
        try await transport.notify(method: "notifications/initialized")
        initialized = true
    }

    public func tools() async throws -> [any AIToolProtocol] {
        try await connect()
        var collected: [any AIToolProtocol] = []
        var cursor: String?
        repeat {
            let params: JSONValue = cursor.map { .object(["cursor": .string($0)]) } ?? .object([:])
            let result = try await request(method: "tools/list", params: params)
            for tool in result["tools"]?.arrayValue ?? [] {
                guard let name = tool["name"]?.stringValue else { continue }
                collected.append(MCPTool(
                    name: name,
                    description: tool["description"]?.stringValue ?? "",
                    parameters: tool["inputSchema"] ?? ["type": "object"],
                    client: self
                ))
            }
            cursor = result["nextCursor"]?.stringValue
        } while cursor != nil
        return collected
    }

    public func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try await connect()
        let result = try await request(method: "tools/call", params: .object([
            "name": .string(name),
            "arguments": arguments
        ]))
        if result["isError"]?.boolValue == true {
            throw AIError.transport("MCP tool \(name) failed: \(textContent(of: result))")
        }
        if let structured = result["structuredContent"] { return structured }
        return .string(textContent(of: result))
    }

    private func textContent(of result: JSONValue) -> String {
        (result["content"]?.arrayValue ?? [])
            .compactMap { part in
                part["type"]?.stringValue == "text" ? part["text"]?.stringValue : nil
            }
            .joined(separator: "\n")
    }

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let response = try await transport.request(id: id, method: method, params: params)
        if let error = response["error"] {
            throw AIError.transport(
                "MCP \(method) error \(error["code"]?.intValue ?? 0): "
                + (error["message"]?.stringValue ?? "unknown")
            )
        }
        return response["result"] ?? .object([:])
    }
}

struct MCPTool: AIToolProtocol {
    let name: String
    let description: String
    let parameters: JSONValue
    let client: MCPClient

    func execute(_ arguments: JSONValue) async throws -> JSONValue {
        try await client.callTool(name: name, arguments: arguments)
    }
}

public actor MCPHTTPTransport: MCPTransport {
    private let url: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private var sessionID: String?

    public init(url: URL, headers: [String: String] = [:], urlSession: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.urlSession = urlSession
    }

    public func request(id: Int, method: String, params: JSONValue) async throws -> JSONValue {
        let body: JSONValue = .object([
            "jsonrpc": "2.0",
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        let (data, response) = try await urlSession.data(for: makeRequest(body: body))
        guard let http = response as? HTTPURLResponse else {
            throw AIError.transport("MCP transport got a non-HTTP response")
        }
        if let session = http.value(forHTTPHeaderField: "mcp-session-id") {
            sessionID = session
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let contentType = http.value(forHTTPHeaderField: "content-type") ?? ""
        if contentType.contains("text/event-stream") {
            return try Self.responseFromSSE(data, id: id)
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func notify(method: String) async throws {
        let body: JSONValue = .object([
            "jsonrpc": "2.0",
            "method": .string(method)
        ])
        _ = try? await urlSession.data(for: makeRequest(body: body))
    }

    private func makeRequest(body: JSONValue) throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            urlRequest.setValue(sessionID, forHTTPHeaderField: "mcp-session-id")
        }
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    static func responseFromSSE(_ data: Data, id: Int) throws -> JSONValue {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        var lineBuffer: [UInt8] = []
        func feedLine() {
            if lineBuffer.last == 0x0D { lineBuffer.removeLast() }
            let line = String(decoding: lineBuffer, as: UTF8.self)
            lineBuffer.removeAll(keepingCapacity: true)
            if let event = parser.feed(line) { events.append(event) }
        }
        for byte in data {
            if byte == 0x0A { feedLine() } else { lineBuffer.append(byte) }
        }
        if !lineBuffer.isEmpty { feedLine() }
        if let event = parser.flush() { events.append(event) }

        for event in events {
            guard let payload = try? JSONDecoder().decode(
                JSONValue.self, from: Data(event.data.utf8)
            ) else { continue }
            if payload["id"]?.intValue == id {
                return payload
            }
        }
        throw AIError.decoding("MCP SSE response did not contain an answer for request \(id)")
    }
}
