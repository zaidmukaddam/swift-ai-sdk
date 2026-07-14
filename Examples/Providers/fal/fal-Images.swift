import AI
import Foundation

enum FalExamples {
    static func images() async throws {
        let result = try await generateImage(
            model: FalImageModel("fal-ai/bytedance/seedream/v4.5/text-to-image"),
            prompt: "A tiny observatory on a snowy mountain",
            aspectRatio: "16:9",
            seed: 7,
            providerOptions: ["fal": ["num_inference_steps": 28]]
        )
        try result.image.write(to: URL(fileURLWithPath: "/tmp/fal-image.png"))
    }
}

