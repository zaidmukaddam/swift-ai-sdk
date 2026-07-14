import AI
import Foundation

extension AIGatewayExamples {
    static func toolsStructuredOutputAndVision() async throws {
        let model = AIGatewayModel("anthropic/claude-sonnet-5")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Pune.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift actors."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: model,
            messages: [Message(role: .user, content: [
                .text("Describe the image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}
