import AI

extension XAIExamples {
    static func realtimeClientSecret() async throws -> RealtimeClientSecret {
        try await XaiRealtimeModel("grok-voice-latest").createClientSecret(
            options: RealtimeClientSecretOptions(expiresAfterSeconds: 300)
        )
    }

    @available(iOS 17.0, macOS 14.0, *)
    @MainActor
    static func realtimeSession(secret: RealtimeClientSecret) -> RealtimeSession {
        let session = RealtimeSession(
            model: XaiRealtimeModel("grok-voice-latest"),
            sessionConfig: RealtimeSessionConfig(instructions: "Be concise.")
        )
        session.connect(secret: secret)
        session.sendText("Say hello in one sentence.")
        return session
    }
}
