import AI

extension GoogleExamples {
    static func realtimeClientSecret() async throws -> RealtimeClientSecret {
        try await GoogleRealtimeModel("gemini-3.1-flash-live-preview").createClientSecret(
            options: RealtimeClientSecretOptions(
                expiresAfterSeconds: 300,
                sessionConfig: RealtimeSessionConfig(
                    instructions: "Be concise.",
                    tools: getRealtimeToolDefinitions(tools: [exampleWeatherTool()])
                )
            )
        )
    }

    @available(iOS 17.0, macOS 14.0, *)
    @MainActor
    static func realtimeSession(secret: RealtimeClientSecret) -> RealtimeSession {
        let session = RealtimeSession(
            model: GoogleRealtimeModel("gemini-3.1-flash-live-preview"),
            sessionConfig: RealtimeSessionConfig(
                instructions: "Be concise.",
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
