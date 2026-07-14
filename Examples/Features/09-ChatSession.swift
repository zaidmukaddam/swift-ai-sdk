import AI
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_remoteChat() {
    let chat = ChatSession(transport: HTTPChatTransport(
        api: URL(string: "https://your-app.vercel.app/api/chat")!,
        headers: ["Authorization": "Bearer token"],
        body: ["sessionId": "abc123"]
    ))

    chat.send("Hello from Swift!")
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_localChat() {
    let model: any LanguageModel
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        model = FoundationModelsModel.orFallback(AnthropicModel("claude-sonnet-5", apiKey: myKey))
    } else {
        model = AnthropicModel("claude-sonnet-5", apiKey: myKey)
    }
    #else
    model = AnthropicModel("claude-sonnet-5", apiKey: myKey)
    #endif

    let chat = ChatSession(transport: LocalChatTransport(
        model: model,
        system: "You are a helpful assistant."
    ))

    chat.send("Hello from the device!")
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_renderMessage(_ message: UIMessage) {
    for part in message.parts {
        switch part {
        case .text(let text):
            print(text.text, text.state == .streaming ? "..." : "")
        case .reasoning(let reasoning):
            print("(thinking) \(reasoning.text)")
        case .tool(let tool):
            print("[\(tool.toolName): \(tool.state.rawValue)]")
        case .stepStart:
            print("---")
        default:
            break
        }
    }
}
