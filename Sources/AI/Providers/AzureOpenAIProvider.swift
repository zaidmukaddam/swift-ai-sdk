import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AzureOpenAIProvider: Sendable {
    public var resourceName: String
    public var apiKey: String?
    public var baseURL: URL?
    public var apiVersion: String
    public var useDeploymentBasedUrls: Bool
    public var headers: [String: String]
    private let urlSession: URLSession

    public init(
        resourceName: String? = nil,
        apiKey: String? = nil,
        baseURL: URL? = nil,
        apiVersion: String = "v1",
        useDeploymentBasedUrls: Bool = false,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.resourceName = resourceName
            ?? ProcessInfo.processInfo.environment["AZURE_RESOURCE_NAME"] ?? ""
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["AZURE_API_KEY"]
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.useDeploymentBasedUrls = useDeploymentBasedUrls
        self.headers = headers
        self.urlSession = urlSession
    }

    public func callAsFunction(_ deploymentID: String) -> OpenAIChatModel {
        languageModel(deploymentID)
    }

    public func languageModel(_ deploymentID: String) -> OpenAIChatModel {
        OpenAIChatModel(
            deploymentID,
            apiKey: "",
            baseURL: engineBaseURL(for: deploymentID),
            headers: engineHeaders,
            queryParams: engineQueryParams,
            urlSession: urlSession,
            providerName: "azure"
        )
    }

    public func textEmbeddingModel(_ deploymentID: String) -> OpenAIEmbeddingModel {
        OpenAIEmbeddingModel(
            deploymentID,
            apiKey: "",
            baseURL: engineBaseURL(for: deploymentID),
            headers: engineHeaders,
            urlSession: urlSession,
            providerName: "azure"
        )
    }

    var isAzureEndpoint: Bool {
        guard let baseURL else { return true }
        return (baseURL.host ?? "").hasSuffix(".openai.azure.com")
    }

    func engineBaseURL(for deploymentID: String) -> URL {
        var prefix: String
        if let baseURL {
            prefix = baseURL.absoluteString
            if prefix.hasSuffix("/") { prefix.removeLast() }
        } else {
            prefix = "https://\(resourceName).openai.azure.com/openai"
        }
        if useDeploymentBasedUrls {
            prefix += "/deployments/\(deploymentID)"
        } else if isAzureEndpoint {
            prefix += "/v1"
        }
        guard let url = URL(string: prefix) else {
            preconditionFailure("Invalid Azure OpenAI base URL: \(prefix)")
        }
        return url
    }

    var engineQueryParams: [String: String] {
        (isAzureEndpoint || useDeploymentBasedUrls) ? ["api-version": apiVersion] : [:]
    }

    var engineHeaders: [String: String] {
        var merged: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { merged["api-key"] = apiKey }
        for (field, value) in headers { merged[field] = value }
        return merged
    }
}
