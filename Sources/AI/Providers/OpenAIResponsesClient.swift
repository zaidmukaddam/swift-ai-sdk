import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIResponsesClient: Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func retrieve(
        _ responseID: String,
        include: [String] = []
    ) async throws -> JSONValue {
        var query: [URLQueryItem] = include.map { URLQueryItem(name: "include[]", value: $0) }
        return try await send("GET", "responses/\(responseID)", query: query.isEmpty ? nil : query)
    }

    @discardableResult
    public func delete(_ responseID: String) async throws -> Bool {
        let json = try await send("DELETE", "responses/\(responseID)")
        return json["deleted"]?.boolValue ?? true
    }

    public func cancel(_ responseID: String) async throws -> JSONValue {
        try await send("POST", "responses/\(responseID)/cancel")
    }

    public func compact(
        _ responseID: String,
        providerOptions: JSONValue? = nil
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = [:]
        if case .object(let options)? = providerOptions {
            for (key, value) in options { body[key] = value }
        }
        return try await send("POST", "responses/\(responseID)/compact", json: .object(body))
    }

    public func listInputItems(
        _ responseID: String,
        limit: Int? = nil,
        order: String? = nil,
        after: String? = nil,
        before: String? = nil,
        include: [String] = []
    ) async throws -> JSONValue {
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let order { query.append(URLQueryItem(name: "order", value: order)) }
        if let after { query.append(URLQueryItem(name: "after", value: after)) }
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        query += include.map { URLQueryItem(name: "include[]", value: $0) }
        return try await send(
            "GET", "responses/\(responseID)/input_items", query: query.isEmpty ? nil : query
        )
    }

    public func countInputTokens(
        for request: LanguageModelRequest,
        modelID: String
    ) async throws -> Int {
        var body = OpenAIModel.responsesBody(for: request, modelID: modelID).objectValue ?? [:]
        body["stream"] = nil
        let json = try await send("POST", "responses/input_tokens", json: .object(body))
        guard let count = json["input_tokens"]?.intValue else {
            throw AIError.decoding("OpenAI input_tokens response had no input_tokens field")
        }
        return count
    }

    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem]? = nil,
        json: JSONValue? = nil
    ) async throws -> JSONValue {
        var url = baseURL.appendingPathComponent(path)
        if let query, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            if let built = components.url { url = built }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(json)
        }
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data.isEmpty ? .object([:]) : try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
