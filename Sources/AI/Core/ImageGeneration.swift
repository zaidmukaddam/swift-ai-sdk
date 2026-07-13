import Foundation

public protocol ImageModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse
}

public struct ImageModelRequest: Sendable {
    public var prompt: String
    public var images: [ImageContent]
    public var n: Int
    public var size: String?
    public var aspectRatio: String?
    public var seed: Int?
    public var providerOptions: JSONValue?

    public init(
        prompt: String,
        images: [ImageContent] = [],
        n: Int = 1,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        providerOptions: JSONValue? = nil
    ) {
        self.prompt = prompt
        self.images = images
        self.n = n
        self.size = size
        self.aspectRatio = aspectRatio
        self.seed = seed
        self.providerOptions = providerOptions
    }
}

public struct ImageModelResponse: Sendable {
    public var images: [Data]
    public var revisedPrompts: [String?]

    public init(images: [Data], revisedPrompts: [String?] = []) {
        self.images = images
        self.revisedPrompts = revisedPrompts
    }
}

public struct GenerateImageResult: Sendable {
    public var image: Data
    public var images: [Data]
    public var revisedPrompts: [String?]
}

public func generateImage(
    model: any ImageModel,
    prompt: String,
    images: [ImageContent] = [],
    n: Int = 1,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateImageResult {
    let request = ImageModelRequest(
        prompt: prompt,
        images: images,
        n: n,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        providerOptions: providerOptions
    )
    let response = try await Retry.withRetries(maxRetries) {
        try await model.generateImages(request)
    }
    guard let first = response.images.first else {
        throw AIError.decoding("Image response contained no images")
    }
    return GenerateImageResult(
        image: first,
        images: response.images,
        revisedPrompts: response.revisedPrompts
    )
}
