import AI

enum AssemblyAIExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/audio.mp3")
        let result = try await transcribe(
            model: AssemblyAITranscriptionModel("universal-3-5-pro"),
            audio: audio,
            mediaType: "audio/mpeg",
            providerOptions: ["speaker_labels": true]
        )
        print(result.text)
        print(result.segments)
    }
}

