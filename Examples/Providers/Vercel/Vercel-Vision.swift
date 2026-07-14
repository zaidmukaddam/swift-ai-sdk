import AI
import Foundation

extension VercelExamples {
    static func vision() async throws {
        let image = try exampleData(at: "/tmp/interface.png")
        let result = try await generateText(
            model: VercelModel("v0-1.5-lg"),
            messages: [Message(role: .user, content: [
                .text("Recreate this interface and explain the component structure."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(result.text)
    }
}
