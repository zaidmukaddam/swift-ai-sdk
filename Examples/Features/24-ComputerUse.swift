import AI
import Foundation

enum ComputerUseExamples {
    static func openAIComputerUse(screenshot: @Sendable (JSONValue) async throws -> Data) async throws {
        var messages: [Message] = [.user("Open the settings page.")]
        let model = OpenAIModel("gpt-5.6-sol")

        for _ in 0..<10 {
            let result = try await generateText(
                model: model,
                messages: messages,
                tools: [OpenAIModel.Tools.computerUse(displayWidth: 1280, displayHeight: 800)]
            )
            guard let call = result.toolCalls.first(where: { $0.name == "computer_use_preview" }) else {
                print(result.text)
                break
            }

            let png = try await screenshot(call.arguments["action"] ?? .object([:]))
            messages.append(Message(role: .assistant, content: [.toolCall(call)]))
            messages.append(Message(role: .tool, content: [.toolResult(ToolResult(
                toolCallID: call.id, name: call.name, output: .null,
                content: [.image(ImageContent(data: png, mediaType: "image/png"))]
            ))]))
        }
    }

    static func anthropicComputerUse() async throws {
        let result = try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: "Take a screenshot and describe what you see.",
            tools: [
                AnthropicModel.Tools.computer(displayWidthPx: 1280, displayHeightPx: 800),
                AnthropicModel.Tools.bash()
            ]
        )
        print(result.toolCalls.map(\.name))
    }
}
