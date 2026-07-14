import AI

enum VercelExamples {
    static func text() async throws {
        let result = streamText(
            model: VercelModel("v0-1.5-lg"),
            prompt: "Build a responsive Swift documentation landing page."
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
