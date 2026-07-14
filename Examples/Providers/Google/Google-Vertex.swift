import AI

extension GoogleExamples {
    static func vertexAI() async throws {
        let model = GoogleVertexModel(
            "gemini-3.5-flash",
            project: "my-project",
            location: "us-central1"
        )
        let result = try await generateText(model: model, prompt: "Say hello from Vertex AI.")
        print(result.text)
    }
}

