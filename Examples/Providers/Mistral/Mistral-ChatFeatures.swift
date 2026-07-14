import AI
import Foundation

extension MistralExamples {
    static func toolsStructuredOutputAndVision() async throws {
        let model = MistralModel("mistral-medium-3.5")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Marseille.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift macros."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: MistralModel("pixtral-large"),
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}
