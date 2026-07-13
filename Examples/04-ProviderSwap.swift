import AI
import Foundation

func example_swapProviders() -> [any LanguageModel] {
    [
        AnthropicModel("claude-opus-4-8"),
        OpenAIModel("gpt-5.6-sol"),
        XaiModel("grok-4.5"),
        GroqModel("llama-3.3-70b-versatile"),
        DeepSeekModel("deepseek-chat"),
        OpenAICompatibleProvider.togetherAI()("meta-llama/Llama-3.3-70B-Instruct-Turbo"),
        OpenAICompatibleProvider.fireworks()("accounts/fireworks/models/llama-v3p3-70b-instruct"),
        OpenAICompatibleProvider.cerebras()("llama-3.3-70b"),
        MistralModel("mistral-large-latest"),
        PerplexityModel("sonar"),
        OpenAICompatibleProvider.openRouter()("anthropic/claude-sonnet-5"),
        GoogleModel("gemini-2.5-flash"),
        OpenAICompatibleProvider.ollama()("llama3.3"),
        OpenAICompatibleProvider.lmStudio()("qwen2.5-7b-instruct")
    ]
}

func example_customProvider() -> OpenAIChatModel {
    let gateway = OpenAICompatibleProvider(
        name: "my-gateway",
        baseURL: URL(string: "https://llm.your-company.com/v1")!,
        apiKey: ProcessInfo.processInfo.environment["GATEWAY_KEY"],
        headers: ["x-team": "ios"],
        queryParams: ["api-version": "2026-01-01"]
    )
    return gateway("my-model")
}

func example_sameCodeEveryProvider() async throws {
    for model in example_swapProviders().prefix(3) {
        let result = try await generateText(model: model, prompt: "Say hi in 3 words.")
        print("\(model.provider)/\(model.modelID): \(result.text)")
    }
}
