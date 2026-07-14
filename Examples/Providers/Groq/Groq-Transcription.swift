import AI
import Foundation

extension GroqExamples {
    static func transcription() async throws {
        let audio = try exampleData(at: "/tmp/audio.mp3")
        let model = OpenAITranscriptionModel(
            "whisper-large-v3-turbo",
            apiKey: ProcessInfo.processInfo.environment["GROQ_API_KEY"],
            baseURL: URL(string: "https://api.groq.com/openai/v1")!
        )
        let result = try await transcribe(
            model: model,
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(result.text)
    }
}

