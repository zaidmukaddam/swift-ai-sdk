import Foundation

public protocol VideoModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse
}

public struct VideoModelRequest: Sendable {
    public var prompt: String
    public var image: ImageContent?
    public var aspectRatio: String?
    public var duration: Int?
    public var providerOptions: JSONValue?

    public init(
        prompt: String,
        image: ImageContent? = nil,
        aspectRatio: String? = nil,
        duration: Int? = nil,
        providerOptions: JSONValue? = nil
    ) {
        self.prompt = prompt
        self.image = image
        self.aspectRatio = aspectRatio
        self.duration = duration
        self.providerOptions = providerOptions
    }
}

public struct VideoModelResponse: Sendable {
    public var urls: [URL]
    public var videos: [Data]
    public var mediaType: String

    public init(urls: [URL] = [], videos: [Data] = [], mediaType: String = "video/mp4") {
        self.urls = urls
        self.videos = videos
        self.mediaType = mediaType
    }
}

public struct GenerateVideoResult: Sendable {
    public var video: Data?
    public var videos: [Data]
    public var urls: [URL]
    public var mediaType: String
}

public func generateVideo(
    model: any VideoModel,
    prompt: String,
    image: ImageContent? = nil,
    aspectRatio: String? = nil,
    duration: Int? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateVideoResult {
    let request = VideoModelRequest(
        prompt: prompt, image: image, aspectRatio: aspectRatio,
        duration: duration, providerOptions: providerOptions
    )
    let response = try await Retry.withRetries(maxRetries) {
        try await model.generateVideos(request)
    }
    guard !response.urls.isEmpty || !response.videos.isEmpty else {
        throw AIError.decoding("Video generation returned no videos")
    }
    return GenerateVideoResult(
        video: response.videos.first,
        videos: response.videos,
        urls: response.urls,
        mediaType: response.mediaType
    )
}
