import AI

extension AmazonBedrockExamples {
    static func toolsStructuredOutputAndVision() async throws {
        let model = BedrockModel(
            "anthropic.claude-sonnet-4-5-20250929-v1:0",
            region: "us-east-1"
        )

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Mumbai.",
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

