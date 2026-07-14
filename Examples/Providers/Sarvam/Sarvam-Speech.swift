import AI
import Foundation

extension SarvamExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: SarvamSpeechModel("bulbul:v3", targetLanguage: "hi-IN"),
            text: "नमस्ते, आप कैसे हैं?",
            voice: "anushka",
            speed: 1.1,
            outputFormat: "mp3",
            providerOptions: [
                "temperature": 0.7,
                "pitch": 0.1
            ]
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/sarvam-speech.mp3"))
    }
}

