import AI
import Foundation

enum LMNTExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: LMNTSpeechModel("blizzard"),
            text: "Your order is ready.",
            voice: "ava",
            speed: 1.0,
            outputFormat: "mp3"
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/lmnt-speech.mp3"))
    }
}

