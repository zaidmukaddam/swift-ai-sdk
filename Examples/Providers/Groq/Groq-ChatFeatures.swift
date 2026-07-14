import AI

extension GroqExamples {
    static func toolsStructuredOutputAndVision() async throws {
        _ = try await generateText(
            model: GroqModel("openai/gpt-oss-120b"),
            prompt: "Check the weather in Mumbai.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: GroqModel("openai/gpt-oss-120b"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift concurrency."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: GroqModel("meta-llama/llama-4-scout-17b-16e-instruct"),
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}

