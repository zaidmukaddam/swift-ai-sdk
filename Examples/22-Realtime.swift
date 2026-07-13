import AI
import Foundation

func example_realtimeToken() async throws -> RealtimeClientSecret {
    let model = OpenAIRealtimeModel("gpt-realtime")
    return try await model.createClientSecret(options: RealtimeClientSecretOptions(
        expiresAfterSeconds: 300,
        sessionConfig: RealtimeSessionConfig(
            tools: getRealtimeToolDefinitions(tools: [weatherTool()])
        )
    ))
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_realtimeSession(secret: RealtimeClientSecret) async throws {
    let session = RealtimeSession(
        model: OpenAIRealtimeModel("gpt-realtime"),
        sessionConfig: RealtimeSessionConfig(
            instructions: "You are a helpful assistant. Be concise.",
            voice: "alloy",
            inputAudioTranscription: .init(),
            turnDetection: .init(type: .serverVAD)
        ),
        onToolCall: { call in
            call.name == "getWeather" ? .string("sunny, 31 C") : nil
        }
    )

    session.connect(secret: secret)
    session.sendText("What is the weather in Mumbai?")

    Task {
        for await chunk in session.audioOutput {
            _ = chunk
        }
    }
}

func example_realtimeProviders() {
    _ = OpenAIRealtimeModel("gpt-realtime")
    _ = GoogleRealtimeModel("gemini-3.1-flash-live-preview")
    _ = XaiRealtimeModel("grok-voice-latest")
}

private func weatherTool() -> Tool {
    Tool(
        name: "getWeather",
        description: "Get the current weather for a city.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "city": .object(["type": .string("string")])
            ])
        ])
    ) { _ in .string("sunny") }
}
