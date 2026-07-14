import AI

extension XAIExamples {
    static func structuredOutputAndVision() async throws {
        let summary = try await generateObject(
            model: XaiModel("grok-4.5"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift actors."
        )
        print(summary.object)

        let image = try exampleData(at: "/tmp/example.png")
        let vision = try await generateText(
            model: XaiModel("grok-4.5"),
            messages: [Message(role: .user, content: [
                .text("Describe this image."),
                .image(ImageContent(data: image, mediaType: "image/png"))
            ])]
        )
        print(vision.text)
    }
}

