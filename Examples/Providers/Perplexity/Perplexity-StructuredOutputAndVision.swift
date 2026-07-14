import AI

extension PerplexityExamples {
    static func structuredOutputAndVision() async throws {
        let summary = try await generateObject(
            model: PerplexityModel("sonar-pro"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift concurrency."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: PerplexityModel("sonar-pro"),
            messages: [Message(role: .user, content: [
                .text("Explain this image with current supporting sources."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}

