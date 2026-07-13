import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GoogleVertexModel: LanguageModel {
    public let provider = "google.vertex"
    public let modelID: String

    private enum Auth: Sendable {
        case apiKey(String)
        case bearer(String)
        case none
    }

    private let auth: Auth
    private let project: String?
    private let location: String
    private let baseURL: URL?
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        project: String? = nil,
        location: String? = nil,
        apiKey: String? = nil,
        accessToken: String? = nil,
        baseURL: URL? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        let env = ProcessInfo.processInfo.environment
        self.project = project ?? env["GOOGLE_VERTEX_PROJECT"]
        self.location = location ?? env["GOOGLE_VERTEX_LOCATION"] ?? "global"
        if let key = apiKey ?? env["GOOGLE_VERTEX_API_KEY"], !key.isEmpty {
            self.auth = .apiKey(key)
        } else if let accessToken, !accessToken.isEmpty {
            self.auth = .bearer(accessToken)
        } else {
            self.auth = .none
        }
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        try await GoogleModel.streamGenerateContent(
            buildURLRequest(request), urlSession: urlSession
        )
    }

    func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        let base = try resolvedBaseURL()
        guard let url = URL(
            string: "\(base)/\(Self.modelPath(modelID)):streamGenerateContent?alt=sse"
        ) else {
            throw AIError.invalidRequest("could not build Vertex URL for model \(modelID)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        switch auth {
        case .apiKey(let key):
            urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .bearer(let token):
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .none:
            break
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(GoogleModel.requestBody(for: request, modelID: modelID))
        return urlRequest
    }

    func resolvedBaseURL() throws -> String {
        let isTunedModel = modelID.hasPrefix("endpoints/")
        if case .apiKey = auth, isTunedModel {
            throw AIError.invalidRequest(
                "Google Vertex tuned models do not support Express Mode API keys."
            )
        }
        if let baseURL {
            let string = baseURL.absoluteString
            return string.hasSuffix("/") ? String(string.dropLast()) : string
        }
        if case .apiKey = auth {
            return "https://aiplatform.googleapis.com/v1/publishers/google"
        }
        guard let project, !project.isEmpty else {
            throw AIError.invalidRequest(
                "Google Vertex needs a project: pass project: or set GOOGLE_VERTEX_PROJECT."
            )
        }
        let host = switch location {
        case "global": "aiplatform.googleapis.com"
        case "eu", "us": "aiplatform.\(location).rep.googleapis.com"
        default: "\(location)-aiplatform.googleapis.com"
        }
        let root = "https://\(host)/v1beta1/projects/\(project)/locations/\(location)"
        return isTunedModel ? root : "\(root)/publishers/google"
    }

    static func modelPath(_ modelID: String) -> String {
        modelID.contains("/") ? modelID : "models/\(modelID)"
    }
}
