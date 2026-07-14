import AI

enum GladiaExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/audio.wav")
        let result = try await transcribe(
            model: GladiaTranscriptionModel("solaria-3"),
            audio: audio,
            mediaType: "audio/wav",
            providerOptions: ["detect_language": true]
        )
        print(result.text)
        print(result.language ?? "unknown language")
    }
}

