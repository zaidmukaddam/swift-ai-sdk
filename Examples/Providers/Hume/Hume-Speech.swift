import AI
import Foundation

enum HumeExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: HumeSpeechModel(),
            text: "I cannot believe we made it!",
            voice: "your-hume-voice-id",
            instructions: "Relieved, warm, and slightly breathless",
            speed: 0.95,
            outputFormat: "mp3"
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/hume-speech.mp3"))
    }
}

