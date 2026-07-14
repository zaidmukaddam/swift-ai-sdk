import AI
import Foundation

extension OpenAIExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: OpenAISpeechModel("gpt-4o-mini-tts"),
            text: "Welcome to Swift AI.",
            voice: "alloy",
            instructions: "Warm and conversational",
            outputFormat: "mp3"
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/openai-speech.mp3"))
    }
}

