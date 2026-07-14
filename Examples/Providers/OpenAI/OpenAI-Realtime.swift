import AI

extension OpenAIExamples {
    static func realtimeClientSecret() async throws -> RealtimeClientSecret {
        try await OpenAIRealtimeModel("gpt-realtime").createClientSecret(
            options: RealtimeClientSecretOptions(
                expiresAfterSeconds: 300,
                sessionConfig: RealtimeSessionConfig(
                    instructions: "Be concise.",
                    voice: "alloy",
                    tools: getRealtimeToolDefinitions(tools: [exampleWeatherTool()])
                )
            )
        )
    }

    @available(iOS 17.0, macOS 14.0, *)
    @MainActor
    static func realtimeSession(secret: RealtimeClientSecret) -> RealtimeSession {
        let session = RealtimeSession(
            model: OpenAIRealtimeModel("gpt-realtime"),
            sessionConfig: RealtimeSessionConfig(
                instructions: "Be concise.",
                voice: "alloy",
                inputAudioTranscription: .init(),
                turnDetection: .init(type: .serverVAD),
                tools: getRealtimeToolDefinitions(tools: [exampleWeatherTool()])
            ),
            onToolCall: { call in
                guard call.name == "getWeather" else { return nil }
                return try await exampleWeatherTool().execute(call.arguments)
            }
        )
        session.connect(secret: secret)
        session.sendText("Say hello in one sentence.")
        return session
    }
}
