import AI

extension AnthropicExamples {
    static func visionAndPDF() async throws {
        let image = try exampleData(at: "/tmp/example.png")
        let pdf = try exampleData(at: "/tmp/report.pdf")

        let result = try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            messages: [Message(role: .user, content: [
                .text("Compare this image with the attached report."),
                .image(ImageContent(data: image, mediaType: "image/png")),
                .file(FileContent(data: pdf, mediaType: "application/pdf", filename: "report.pdf"))
            ])]
        )
        print(result.text)
    }
}

