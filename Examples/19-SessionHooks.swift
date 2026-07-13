import AI
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_completionSession() {
    let remote = CompletionSession(transport: HTTPCompletionTransport(
        api: URL(string: "https://your-app.vercel.app/api/completion")!
    ))
    remote.complete("Write a tagline for a coffee shop")

    let local = CompletionSession(model: AnthropicModel("claude-sonnet-5"))
    local.complete("Write a tagline for a bookstore")
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_objectSession() {
    struct Notification: Decodable {
        var title: String
        var body: String
    }

    let session = ObjectSession(
        model: OpenAIModel("gpt-5.6-sol"),
        schema: Schema.object([
            "title": .string(),
            "body": .string()
        ])
    )
    session.submit("A notification about a delayed flight")

    if let title = session.object?["title"]?.stringValue {
        print("so far:", title)
    }
    if let notification = session.decoded(Notification.self) {
        print(notification.title, "-", notification.body)
    }
}
