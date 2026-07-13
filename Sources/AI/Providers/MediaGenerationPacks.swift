import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct FalImageModel: ImageModel {
    public let provider = "fal"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://fal.run")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
            ?? ProcessInfo.processInfo.environment["FAL_API_KEY"]
            ?? ProcessInfo.processInfo.environment["FAL_KEY"]
            ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        let urls = (decoded["images"]?.arrayValue ?? [])
            .compactMap { $0["url"]?.stringValue }
            .compactMap(URL.init(string:))
        guard !urls.isEmpty else {
            throw AIError.decoding("fal returned no images")
        }
        var images: [Data] = []
        for url in urls {
            let (bytes, _) = try await urlSession.data(from: url)
            images.append(bytes)
        }
        return ImageModelResponse(images: images)
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "prompt": .string(request.prompt),
            "num_images": .number(Double(request.n))
        ]
        if let size = request.size {
            let parts = size.split(separator: "x")
            if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                body["image_size"] = .object([
                    "width": .number(Double(width)), "height": .number(Double(height))
                ])
            }
        }
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let options = request.providerOptions?["fal"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(modelID))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct LumaImageModel: ImageModel {
    public let provider = "luma"
    public let modelID: String

    let engine: LumaGenerationEngine

    public init(
        _ modelID: String = "photon-1",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.lumalabs.ai")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 2,
        pollTimeout: TimeInterval = 300,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.engine = LumaGenerationEngine(
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["LUMA_API_KEY"] ?? "",
            baseURL: baseURL, headers: headers,
            pollInterval: pollInterval, pollTimeout: pollTimeout, urlSession: urlSession
        )
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        var body: [String: JSONValue] = [
            "prompt": .string(request.prompt),
            "model": .string(modelID)
        ]
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let options = request.providerOptions?["luma"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }
        let assetURL = try await engine.generate(path: "generations/image", body: .object(body)) {
            $0["assets"]?["image"]?.stringValue
        }
        let (bytes, _) = try await engine.urlSession.data(from: assetURL)
        return ImageModelResponse(images: [bytes])
    }
}

public struct LumaVideoModel: VideoModel {
    public let provider = "luma"
    public let modelID: String

    let engine: LumaGenerationEngine

    public init(
        _ modelID: String = "ray-2",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.lumalabs.ai")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 5,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.engine = LumaGenerationEngine(
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["LUMA_API_KEY"] ?? "",
            baseURL: baseURL, headers: headers,
            pollInterval: pollInterval, pollTimeout: pollTimeout, urlSession: urlSession
        )
    }

    public func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse {
        var body: [String: JSONValue] = [
            "prompt": .string(request.prompt),
            "model": .string(modelID)
        ]
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let duration = request.duration { body["duration"] = .string("\(duration)s") }
        if let image = request.image, let url = image.url {
            body["keyframes"] = .object([
                "frame0": .object(["type": "image", "url": .string(url.absoluteString)])
            ])
        }
        if let options = request.providerOptions?["luma"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }
        let assetURL = try await engine.generate(path: "generations", body: .object(body)) {
            $0["assets"]?["video"]?.stringValue
        }
        return VideoModelResponse(urls: [assetURL], mediaType: "video/mp4")
    }
}

struct LumaGenerationEngine: Sendable {
    var apiKey: String
    var baseURL: URL
    var headers: [String: String]
    var pollInterval: TimeInterval
    var pollTimeout: TimeInterval
    var urlSession: URLSession

    func generate(
        path: String,
        body: JSONValue,
        asset: @Sendable (JSONValue) -> String?
    ) async throws -> URL {
        var create = URLRequest(
            url: baseURL.appendingPathComponent("dream-machine/v1/\(path)")
        )
        create.httpMethod = "POST"
        create.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { create.setValue(value, forHTTPHeaderField: field) }
        create.httpBody = try JSONEncoder().encode(body)

        let (createData, createResponse) = try await urlSession.data(for: create)
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        guard let id = try JSONDecoder().decode(JSONValue.self, from: createData)["id"]?.stringValue
        else { throw AIError.decoding("Luma returned no generation id") }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Date() > deadline { throw AIError.transport("Luma generation timed out") }
            var poll = URLRequest(
                url: baseURL.appendingPathComponent("dream-machine/v1/generations/\(id)")
            )
            poll.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            if let assetURL = try Self.resolvePoll(status, asset: asset) { return assetURL }
        }
    }

    static func resolvePoll(
        _ status: JSONValue,
        asset: (JSONValue) -> String?
    ) throws -> URL? {
        switch status["state"]?.stringValue {
        case "completed":
            guard let urlString = asset(status), let url = URL(string: urlString) else {
                throw AIError.decoding("Luma generation completed without an asset URL")
            }
            return url
        case "failed":
            throw AIError.transport(
                "Luma generation failed: \(status["failure_reason"]?.stringValue ?? "unknown")"
            )
        default:
            return nil
        }
    }
}

public struct ReplicateImageModel: ImageModel {
    public let provider = "replicate"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.replicate.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["REPLICATE_API_TOKEN"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        let output = decoded["output"]
        let urlStrings: [String]
        if let array = output?.arrayValue {
            urlStrings = array.compactMap(\.stringValue)
        } else if let single = output?.stringValue {
            urlStrings = [single]
        } else {
            urlStrings = []
        }
        guard !urlStrings.isEmpty else {
            throw AIError.decoding("Replicate returned no output")
        }
        var images: [Data] = []
        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            let (bytes, _) = try await urlSession.data(from: url)
            images.append(bytes)
        }
        return ImageModelResponse(images: images)
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var input: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if request.n > 1 { input["num_outputs"] = .number(Double(request.n)) }
        if let size = request.size { input["size"] = .string(size) }
        if let aspectRatio = request.aspectRatio { input["aspect_ratio"] = .string(aspectRatio) }
        if let seed = request.seed { input["seed"] = .number(Double(seed)) }
        if let options = request.providerOptions?["replicate"]?.objectValue {
            for (key, value) in options { input[key] = value }
        }
        var body: [String: JSONValue] = ["input": .object(input)]

        let url: URL
        if let colon = modelID.firstIndex(of: ":") {
            body["version"] = .string(String(modelID[modelID.index(after: colon)...]))
            url = baseURL.appendingPathComponent("predictions")
        } else {
            url = baseURL.appendingPathComponent("models/\(modelID)/predictions")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("wait", forHTTPHeaderField: "Prefer")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}
