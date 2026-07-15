import AI

enum CartesiaExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: CartesiaSpeechModel("sonic-2"),
            text: "Hello from Swift.",
            voice: "a0e99841-438c-4a64-b679-ae501e7d6091",
            outputFormat: "wav"
        )
        print(result.mediaType, result.audio.count)
    }

    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/example.wav")
        let result = try await transcribe(
            model: CartesiaTranscriptionModel("ink-whisper"),
            audio: audio,
            mediaType: "audio/wav"
        )
        print(result.text)
    }
}
