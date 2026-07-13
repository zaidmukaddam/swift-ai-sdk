import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct UploadedFile: Sendable, Hashable {
    public var id: String
    public var filename: String?
    public var sizeBytes: Int?
}

public struct OpenAIFiles: Sendable {
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

    public func upload(
        data: Data, filename: String, purpose: String = "user_data",
        mediaType: String = "application/octet-stream"
    ) async throws -> UploadedFile {
        var form = MultipartForm(boundary: "swift-ai-sdk-files")
        form.addField(name: "purpose", value: purpose)
        form.addFile(name: "file", filename: filename, mediaType: mediaType, data: data)

        var request = URLRequest(url: baseURL.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = form.finish()

        let (responseData, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(
                status: http.statusCode, body: String(decoding: responseData, as: UTF8.self)
            )
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: responseData)
        guard let id = decoded["id"]?.stringValue else {
            throw AIError.decoding("OpenAI file upload returned no id")
        }
        return UploadedFile(
            id: id,
            filename: decoded["filename"]?.stringValue,
            sizeBytes: decoded["bytes"]?.intValue
        )
    }

    public func delete(id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("files/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }
}

public struct AnthropicFiles: Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func upload(
        data: Data, filename: String, mediaType: String
    ) async throws -> UploadedFile {
        var form = MultipartForm(boundary: "swift-ai-sdk-files")
        form.addFile(name: "file", filename: filename, mediaType: mediaType, data: data)

        var request = URLRequest(url: baseURL.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("files-api-2025-04-14", forHTTPHeaderField: "anthropic-beta")
        request.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = form.finish()

        let (responseData, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(
                status: http.statusCode, body: String(decoding: responseData, as: UTF8.self)
            )
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: responseData)
        guard let id = decoded["id"]?.stringValue else {
            throw AIError.decoding("Anthropic file upload returned no id")
        }
        return UploadedFile(
            id: id,
            filename: decoded["filename"]?.stringValue,
            sizeBytes: decoded["size_bytes"]?.intValue
        )
    }
}

public struct UploadedSkill: Sendable, Hashable {
    public var id: String
    public var displayTitle: String?
    public var latestVersion: String?
}

public struct SkillFile: Sendable {
    public var path: String
    public var data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

public struct AnthropicSkills: Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func upload(
        files: [SkillFile], displayTitle: String? = nil
    ) async throws -> UploadedSkill {
        var form = MultipartForm(boundary: "swift-ai-sdk-skills")
        if let displayTitle {
            form.addField(name: "display_title", value: displayTitle)
        }
        for file in files {
            form.addFile(
                name: "files[]", filename: file.path,
                mediaType: "application/octet-stream", data: file.data
            )
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("skills"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("skills-2025-10-02", forHTTPHeaderField: "anthropic-beta")
        request.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = form.finish()

        let (responseData, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(
                status: http.statusCode, body: String(decoding: responseData, as: UTF8.self)
            )
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: responseData)
        guard let id = decoded["id"]?.stringValue else {
            throw AIError.decoding("Anthropic skill upload returned no id")
        }
        return UploadedSkill(
            id: id,
            displayTitle: decoded["display_title"]?.stringValue,
            latestVersion: decoded["latest_version"]?.stringValue
        )
    }
}
