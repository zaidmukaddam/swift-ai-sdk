import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct XaiHTTP: Sendable {
    var apiKey: String
    var baseURL: URL
    var headers: [String: String]
    var urlSession: URLSession

    init(apiKey: String?, baseURL: URL, headers: [String: String], urlSession: URLSession) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    private func authorize(_ request: inout URLRequest) {
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
    }

    func send(_ method: String, _ path: String, json: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        authorize(&request)
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(json)
        }
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
        return data.isEmpty ? .object([:]) : try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func download(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        authorize(&request)
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
        return data
    }

    func multipart(_ path: String, form: MultipartForm) async throws -> JSONValue {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        request.httpBody = form.finish()
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
        return data.isEmpty ? .object([:]) : try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }
}

public struct XaiFile: Sendable {
    public var id: String
    public var filename: String?
    public var bytes: Int?
    public var createdAt: Int?
    public var expiresAt: Int?
    public var publicURL: String?
    public var raw: JSONValue

    init?(_ json: JSONValue) {
        guard let id = json["id"]?.stringValue else { return nil }
        self.id = id
        self.filename = json["filename"]?.stringValue
        self.bytes = json["bytes"]?.intValue
        self.createdAt = json["created_at"]?.intValue
        self.expiresAt = json["expires_at"]?.intValue
        self.publicURL = json["public_url"]?.stringValue
        self.raw = json
    }
}

public struct XaiFilesClient: Sendable {
    let http: XaiHTTP

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.http = XaiHTTP(apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession)
    }

    public func upload(
        _ data: Data,
        filename: String,
        mediaType: String = "application/octet-stream",
        expiresAfter: Int? = nil
    ) async throws -> XaiFile {
        var form = MultipartForm(boundary: "swift-ai-sdk-xai-files")
        if let expiresAfter { form.addField(name: "expires_after", value: String(expiresAfter)) }
        form.addFile(name: "file", filename: filename, mediaType: mediaType, data: data)
        let json = try await http.multipart("files", form: form)
        guard let file = XaiFile(json) else {
            throw AIError.decoding("xAI file upload returned no id")
        }
        return file
    }

    public func list() async throws -> [XaiFile] {
        let json = try await http.send("GET", "files")
        let items = json["files"]?.arrayValue ?? json["data"]?.arrayValue ?? []
        return items.compactMap(XaiFile.init)
    }

    public func get(_ fileID: String) async throws -> XaiFile {
        let json = try await http.send("GET", "files/\(fileID)")
        guard let file = XaiFile(json) else {
            throw AIError.decoding("xAI file \(fileID) returned no id")
        }
        return file
    }

    public func download(_ fileID: String) async throws -> Data {
        try await http.download("files/\(fileID)/content")
    }

    @discardableResult
    public func delete(_ fileID: String) async throws -> Bool {
        let json = try await http.send("DELETE", "files/\(fileID)")
        return json["deleted"]?.boolValue ?? true
    }
}

public struct XaiBatchClient: Sendable {
    let http: XaiHTTP

    public struct Request: Sendable {
        public var id: String
        public var endpoint: String
        public var model: String
        public var body: JSONValue

        public init(id: String, endpoint: String = "/v1/chat/completions", model: String, body: JSONValue) {
            self.id = id
            self.endpoint = endpoint
            self.model = model
            self.body = body
        }
    }

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.http = XaiHTTP(apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession)
    }

    public func create(name: String, requests: [Request]) async throws -> String {
        let body: JSONValue = .object([
            "name": .string(name),
            "batch_requests": .array(requests.map { request in
                .object([
                    "batch_request_id": .string(request.id),
                    "endpoint": .string(request.endpoint),
                    "model": .string(request.model),
                    "chat_get_completion": request.body
                ])
            })
        ])
        let json = try await http.send("POST", "batches", json: body)
        guard let batchID = json["batch_id"]?.stringValue else {
            throw AIError.decoding("xAI batch create returned no batch_id")
        }
        return batchID
    }

    public func list() async throws -> JSONValue {
        try await http.send("GET", "batches")
    }

    public func get(_ batchID: String) async throws -> JSONValue {
        try await http.send("GET", "batches/\(batchID)")
    }

    public func requests(_ batchID: String) async throws -> JSONValue {
        try await http.send("GET", "batches/\(batchID)/requests")
    }

    public func results(_ batchID: String) async throws -> JSONValue {
        try await http.send("GET", "batches/\(batchID)/results")
    }
}

public struct XaiCollectionsClient: Sendable {
    let http: XaiHTTP

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.http = XaiHTTP(apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession)
    }

    public func create(
        name: String,
        indexConfiguration: JSONValue? = nil,
        teamID: String? = nil
    ) async throws -> String {
        var body: [String: JSONValue] = ["collection_name": .string(name)]
        if let indexConfiguration { body["index_configuration"] = indexConfiguration }
        if let teamID { body["team_id"] = .string(teamID) }
        let json = try await http.send("POST", "collections", json: .object(body))
        guard let id = json["collection_id"]?.stringValue ?? json["id"]?.stringValue else {
            throw AIError.decoding("xAI collection create returned no collection_id")
        }
        return id
    }

    public func list() async throws -> JSONValue {
        try await http.send("GET", "collections")
    }

    public func get(_ collectionID: String) async throws -> JSONValue {
        try await http.send("GET", "collections/\(collectionID)")
    }

    @discardableResult
    public func delete(_ collectionID: String) async throws -> Bool {
        let json = try await http.send("DELETE", "collections/\(collectionID)")
        return json["deleted"]?.boolValue ?? true
    }

    @discardableResult
    public func addDocument(
        collectionID: String,
        fileID: String,
        metadata: JSONValue? = nil
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = ["file_id": .string(fileID)]
        if let metadata { body["metadata"] = metadata }
        return try await http.send("POST", "collections/\(collectionID)/documents", json: .object(body))
    }

    @discardableResult
    public func removeDocument(collectionID: String, fileID: String) async throws -> Bool {
        let json = try await http.send("DELETE", "collections/\(collectionID)/documents/\(fileID)")
        return json["deleted"]?.boolValue ?? true
    }

    public func search(
        query: String,
        source: JSONValue,
        filter: String? = nil,
        minK: JSONValue? = nil,
        maxK: JSONValue? = nil,
        instructions: String? = nil
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = [
            "query": .string(query),
            "source": source
        ]
        if let filter { body["filter"] = .string(filter) }
        if let minK { body["min_k"] = minK }
        if let maxK { body["max_k"] = maxK }
        if let instructions { body["instructions"] = .string(instructions) }
        return try await http.send("POST", "documents/search", json: .object(body))
    }
}
