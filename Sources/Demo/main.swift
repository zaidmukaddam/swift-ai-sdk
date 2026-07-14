import AI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

let env = ProcessInfo.processInfo.environment

func pickModel() -> (any AI.LanguageModel)? {
    let override = env["AI_MODEL"]

    #if canImport(FoundationModels)
    if env["AI_ON_DEVICE"] != nil {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard FoundationModelsModel.isAvailable else {
                print("Foundation Models unavailable: \(FoundationModelsModel.availability)")
                return nil
            }
            return FoundationModelsModel()
        }
    }
    #if compiler(>=6.4)
    if env["AI_PCC"] != nil {
        if #available(iOS 27.0, macOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            print("PCC availability: \(pcc.availability)")
            guard pcc.isAvailable else { return nil }
            return FoundationModelsModel(privateCloudCompute: pcc)
        }
    }
    #endif
    #endif
    if let key = env["ANTHROPIC_API_KEY"] {
        return AnthropicModel(override ?? "claude-sonnet-5", apiKey: key)
    }
    if let key = env["OPENAI_API_KEY"] {
        return OpenAIModel(override ?? "gpt-4o-mini", apiKey: key)
    }
    if let ollamaModel = env["OLLAMA_MODEL"] ?? override {
        let host = env["OLLAMA_HOST"] ?? "http://localhost:11434"
        guard let baseURL = URL(string: host) else {
            print("Invalid OLLAMA_HOST: \(host)")
            return nil
        }
        return OllamaModel(ollamaModel, baseURL: baseURL.appendingPathComponent("v1"))
    }
    return nil
}

guard let model = pickModel() else {
    print("""
    No provider configured. Set one of:
      ANTHROPIC_API_KEY / OPENAI_API_KEY / OLLAMA_MODEL / AI_ON_DEVICE=1
    """)
    exit(1)
}

print("provider: \(model.provider), model: \(model.modelID)\n")

do {

print("streamText:")
for try await delta in streamText(model: model, prompt: "Write a one-line haiku about Swift.").textStream {
    print(delta, terminator: "")
}
print("\n")

print("tool loop:")
let weather = Tool(
    name: "weather",
    description: "Current weather for a city",
    parameters: ["type": "object",
                 "properties": ["city": ["type": "string"]],
                 "required": ["city"]]
) { args in
    print("  [tool called: weather(\(args["city"]?.stringValue ?? "?"))]")
    return ["tempC": 31, "condition": "sunny"]
}
let toolResult = try await generateText(
    model: model,
    prompt: "What's the weather in Mumbai? Use the weather tool.",
    tools: [weather],
    stopWhen: [stepCountIs(3)]
)
print("  \(toolResult.text)")
print("  steps: \(toolResult.stepCount), tool calls: \(toolResult.toolCalls.count)\n")

print("generateObject:")
struct City: Codable { var name: String; var country: String; var population: Int }
let object = try await generateObject(
    model: model,
    of: City.self,
    schema: [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "country": ["type": "string"],
            "population": ["type": "integer"]
        ],
        "required": ["name", "country", "population"],
        "additionalProperties": false
    ],
    prompt: "The largest city in India."
)
print("  \(object.object.name), \(object.object.country), pop. \(object.object.population)")
print("  usage: \(object.usage.totalTokens) tokens\n")

print("All live checks passed.")

} catch {
    print("\nFAILED: \(error)")
    exit(1)
}
