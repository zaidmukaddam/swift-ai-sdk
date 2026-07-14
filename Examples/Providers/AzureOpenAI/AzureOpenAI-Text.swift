import AI

enum AzureOpenAIExamples {
    static func textToolsStructuredOutputAndVision() async throws {
        let azure = AzureOpenAIProvider(resourceName: "my-resource", apiVersion: "v1")
        let model = azure("my-gpt-5-deployment")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Mumbai.",
            tools: [exampleWeatherTool()],
            reasoning: .high
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
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}

