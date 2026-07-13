import AI
import Foundation

func example_subagents() async throws {
    let model = AnthropicModel("claude-sonnet-5")

    let researcher = Agent(
        model: model,
        instructions: "You research questions and answer with dense facts."
    )
    let writer = Agent(
        model: model,
        instructions: "You turn notes into friendly prose."
    )

    let orchestrator = Agent(
        model: model,
        instructions: "Plan the work, delegate to specialists, then combine.",
        tools: [
            researcher.asTool(
                name: "researcher",
                description: "Delegate a research question to a specialist."
            ),
            writer.asTool(
                name: "writer",
                description: "Delegate drafting to a writing specialist."
            )
        ]
    )

    let result = try await orchestrator.generate(
        prompt: "Write a short primer on tidal energy."
    )
    print(result.text)
}

func example_toolContext() async throws {
    let ordersTool = Tool(
        name: "list_orders",
        description: "List recent orders for the signed-in user.",
        parameters: .object(["type": .string("object")])
    ) { _, options in
        let userID = options.context?["userID"]?.stringValue ?? "anonymous"
        return .string("Orders for \(userID): #1001, #1002")
    }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "What did I order recently?",
        tools: [ordersTool],
        toolsContext: ["list_orders": .object(["userID": .string("user-7")])]
    )
    print(result.text)
}

func example_customProvider() throws {
    let openAI = ProviderRegistry.Provider { OpenAIModel($0) }

    let aliased = customProvider(
        languageModels: [
            "fast": OpenAIModel("gpt-5.6-luna"),
            "smart": OpenAIModel("gpt-5.6-sol")
        ],
        fallback: openAI
    )

    let registry = ProviderRegistry(providers: ["openai": aliased])
    let fast = try registry.languageModel("openai:fast")
    let exact = try registry.languageModel("openai:gpt-5.6-terra")
    print(fast.modelID, exact.modelID)
}
