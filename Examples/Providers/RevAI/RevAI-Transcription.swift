import AI

enum RevAIExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/audio.mp3")
        let result = try await transcribe(
            model: RevAITranscriptionModel("machine"),
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(result.text)
        print(result.segments)
    }

    static func lowCostTranscription() async throws {
        let audio = try exampleData(at: "/tmp/audio.mp3")
        let result = try await transcribe(
            model: RevAITranscriptionModel("low_cost"),
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(result.text)
    }
}

