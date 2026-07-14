import AI
import Foundation

extension OpenAIExamples {
    static func vision() async throws {
        let image = try exampleData(at: "/tmp/example.png")
        let result = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(result.text)
    }
}

