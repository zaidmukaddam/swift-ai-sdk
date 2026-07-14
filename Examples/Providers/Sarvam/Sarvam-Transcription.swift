import AI

extension SarvamExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/sarvam-speech.mp3")
        let result = try await transcribe(
            model: SarvamTranscriptionModel("saaras:v3"),
            audio: audio,
            mediaType: "audio/mpeg",
            providerOptions: [
                "language_code": "hi-IN",
                "mode": "transcribe"
            ]
        )
        print(result.text)
        print(result.language ?? "unknown language")
    }
}

