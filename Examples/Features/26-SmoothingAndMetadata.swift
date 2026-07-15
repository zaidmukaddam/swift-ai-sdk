import AI

enum SmoothingAndMetadataExamples {
    static func smoothStreaming() async throws {
        let result = streamText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "Write a short paragraph about tide pools.",
            onChunk: { part in
                if case .source(let s) = part { print("source:", s.url) }
            },
            onAbort: { print("aborted") }
        )
        for try await word in result.smoothedTextStream(chunking: .word) {
            print(word, terminator: "")
        }
    }

    static func googleGroundingMetadata() async throws {
        let result = try await generateText(
            model: GoogleModel("gemini-3.5-flash"),
            prompt: "What launched in AI this week?",
            tools: [GoogleModel.Tools.googleSearch()]
        )
        print(result.sources.map(\.url))
        print(result.providerMetadata?["google"]?["groundingMetadata"] ?? .null)
    }

    static func openAILogprobs() async throws {
        let result = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "Say hello.",
            providerOptions: ["top_logprobs": .number(3), "include": .array([
                .string("message.output_text.logprobs")
            ])]
        )
        print(result.providerMetadata?["openai"]?["logprobs"] ?? .null)
    }

    static func perplexityImages() async throws {
        let result = try await generateText(
            model: PerplexityModel("sonar-pro"),
            prompt: "Show me photos of the aurora.",
            providerOptions: ["return_images": .bool(true), "return_related_questions": .bool(true)]
        )
        let meta = result.providerMetadata?["perplexity"]
        print(meta?["images"] ?? .null, meta?["related_questions"] ?? .null)
    }
}
