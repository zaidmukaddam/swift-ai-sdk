import AI
import Foundation

enum OpenAICompatibleExamples {
    static func textAndTools() async throws {
        let provider = OpenAICompatibleProvider(
            name: "my-server",
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: ProcessInfo.processInfo.environment["CUSTOM_LLM_API_KEY"]
        )
        let result = try await generateText(
            model: provider("openai/gpt-oss-20b"),
            prompt: "Check the weather in Mumbai.",
            tools: [exampleWeatherTool()]
        )
        print(result.text)
    }
}

