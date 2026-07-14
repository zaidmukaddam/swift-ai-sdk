import AI
import Foundation

enum DeepgramExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: DeepgramSpeechModel("aura-2-thalia-en"),
            text: "The next train arrives in five minutes.",
            outputFormat: "mp3"
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/deepgram-speech.mp3"))
    }
}

