import AI

enum AlibabaExamples {
    static func thinkingChat() async throws {
        let result = try await generateText(
            model: AlibabaModel("qwen3-max"),
            prompt: "Plan a three-day trip to Kyoto.",
            reasoning: .medium
        )
        print(result.text)
    }

    static func embeddings() async throws {
        let vectors = try await embedMany(
            model: AlibabaEmbeddingModel("text-embedding-v4", dimension: 1024),
            values: ["hello world", "swift concurrency"]
        )
        print(vectors.embeddings.count)
    }

    static func video() async throws {
        let video = try await generateVideo(
            model: AlibabaVideoModel("wan2.6-t2v"),
            prompt: "A paper boat sailing down a rain gutter"
        )
        print(video.urls)
    }
}
