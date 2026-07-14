import AI

extension CohereExamples {
    static func toolsStructuredOutputAndVision() async throws {
        _ = try await generateText(
            model: CohereModel("command-a"),
            prompt: "Check the weather in Mumbai.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: CohereModel("command-a"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift generics."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: CohereModel("command-a-vision"),
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}

