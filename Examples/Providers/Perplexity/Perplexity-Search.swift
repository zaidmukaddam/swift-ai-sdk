import AI

enum PerplexityExamples {
    static func searchWithCitations() async throws {
        let result = try await generateText(
            model: PerplexityModel("sonar-pro"),
            prompt: "What changed in the latest Swift release?"
        )
        print(result.text)
        for source in result.sources {
            print(source.title ?? source.url)
        }
    }

    static func reasoning() async throws {
        let result = streamText(
            model: PerplexityModel("sonar-reasoning-pro"),
            prompt: "Compare Swift actors and locks."
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}

