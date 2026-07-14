import AI

extension DeepgramExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/deepgram-speech.mp3")
        let result = try await transcribe(
            model: DeepgramTranscriptionModel("nova-3"),
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(result.text)
        print(result.segments)
    }
}

