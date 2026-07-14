import AI
import Foundation

extension OpenAIExamples {
    static func imageGenerationAndEditing() async throws {
        let generated = try await generateImage(
            model: OpenAIImageModel("gpt-image-2"),
            prompt: "A tiny observatory on a snowy mountain",
            size: "1024x1024"
        )
        try generated.image.write(to: URL(fileURLWithPath: "/tmp/openai-image.png"))

        let source = try exampleData(at: "/tmp/source.png")
        let edited = try await generateImage(
            model: OpenAIImageModel("gpt-image-2"),
            prompt: "Add a red scarf",
            images: [ImageContent(data: source, mediaType: "image/png")]
        )
        try edited.image.write(to: URL(fileURLWithPath: "/tmp/openai-edit.png"))
    }
}

