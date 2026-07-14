import AI
import Foundation

enum ReplicateExamples {
    static func images() async throws {
        let result = try await generateImage(
            model: ReplicateImageModel("openai/gpt-image-2"),
            prompt: "A handmade paper city at sunrise",
            aspectRatio: "16:9",
            seed: 7,
            providerOptions: ["replicate": ["output_format": "png"]]
        )
        try result.image.write(to: URL(fileURLWithPath: "/tmp/replicate-image.png"))
    }
}

