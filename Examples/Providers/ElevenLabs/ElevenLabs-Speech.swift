import AI
import Foundation

enum ElevenLabsExamples {
    static func speech() async throws {
        let result = try await generateSpeech(
            model: ElevenLabsSpeechModel("eleven_v3"),
            text: "Welcome to the show.",
            voice: "21m00Tcm4TlvDq8ikWAM",
            outputFormat: "mp3"
        )
        try result.audio.write(to: URL(fileURLWithPath: "/tmp/elevenlabs-speech.mp3"))
    }
}

