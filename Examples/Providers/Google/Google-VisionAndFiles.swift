import AI

extension GoogleExamples {
    static func visionAndFiles() async throws {
        let image = try exampleData(at: "/tmp/example.png")
        let notes = try exampleData(at: "/tmp/notes.txt")

        let result = try await generateText(
            model: GoogleModel("gemini-3.5-flash"),
            messages: [Message(role: .user, content: [
                .text("Use both attachments to explain the topic."),
                .image(ImageContent(data: image, mediaType: "image/png")),
                .file(FileContent(data: notes, mediaType: "text/plain", filename: "notes.txt"))
            ])]
        )
        print(result.text)
    }
}

