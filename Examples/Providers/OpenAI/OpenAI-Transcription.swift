import AI

extension OpenAIExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/openai-speech.mp3")
        let result = try await transcribe(
            model: OpenAITranscriptionModel("whisper-1"),
            audio: audio,
            mediaType: "audio/mpeg",
            providerOptions: ["openai": ["language": "en"]]
        )
        print(result.text)
    }
}

