import AI
import Foundation

extension OpenAICompatibleExamples {
    static func embeddings() async throws {
        let provider = OpenAICompatibleProvider(
            name: "my-server",
            baseURL: URL(string: "https://llm.example.com/v1")!
        )
        let result = try await embed(
            model: provider.textEmbeddingModel("BAAI/bge-large-en-v1.5"),
            value: "Swift actors"
        )
        print(result.embedding.count)
    }
}

