import AI

enum CohereExamples {
    static func textAndCitations() async throws {
        let result = try await generateText(
            model: CohereModel("command-a"),
            prompt: "Explain Swift actors and cite relevant sources."
        )
        print(result.text)
        print(result.sources)
    }
}
