import AI

extension ElevenLabsExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/elevenlabs-speech.mp3")
        let result = try await transcribe(
            model: ElevenLabsTranscriptionModel("scribe_v2"),
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(result.text)
    }
}

