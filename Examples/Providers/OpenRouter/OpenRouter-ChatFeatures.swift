import AI
import Foundation

extension OpenRouterExamples {
    static func toolsStructuredOutputAndVision() async throws {
        let model = OpenRouterModel("anthropic/claude-sonnet-5")

        _ = try await generateText(
            model: model,
            prompt: "What is the weather in Delhi?",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift concurrency."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: model,
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}
