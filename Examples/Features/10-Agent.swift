import AI
import Foundation

func example_agent() async throws {
    let weather = exampleWeatherTool()

    let assistant = Agent(
        model: AnthropicModel("claude-sonnet-5"),
        instructions: "You are a terse weather assistant.",
        tools: [weather],
        stopWhen: [isStepCount(4)]
    )

    let result = try await assistant.generate(prompt: "Weather in Mumbai?")
    print(result.text)

    for try await delta in assistant.stream(prompt: "And in Tokyo?").textStream {
        print(delta, terminator: "")
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_agentAsChatTransport() {
    let agent = Agent(
        model: AnthropicModel("claude-sonnet-5"),
        instructions: "You are a helpful assistant."
    )
    let chat = ChatSession(transport: agent)
    chat.send("Hello!")
}
