import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MCPClient {
    public let transport: MCPHTTPTransport
    private var initialized = false
    private var nextID = 1

    public init(transport: MCPHTTPTransport) {
        self.transport = transport
    }

    public func connect(
        clientName: String = "swift-ai-sdk", clientVersion: String = "0.1.0"
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
        let result = try await request(method: "tools/list", params: .object([:]))
        let tools = result["tools"]?.arrayValue ?? []
        return tools.compactMap { tool -> (any AIToolProtocol)? in
            guard let name = tool["name"]?.stringValue else { return nil }
            return MCPTool(
                name: name,
                description: tool["description"]?.stringValue ?? "",
                parameters: tool["inputSchema"] ?? ["type": "object"],
                client: self
            )
        }
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

public actor MCPHTTPTransport {
    private let url: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private var sessionID: String?

    public init(url: URL, headers: [String: String] = [:], urlSession: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.urlSession = urlSession
    }

    func request(id: Int, method: String, params: JSONValue) async throws -> JSONValue {
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

    func notify(method: String) async throws {
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
        for line in String(decoding: data, as: UTF8.self).split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            if let event = parser.feed(String(line)) { events.append(event) }
        }
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
