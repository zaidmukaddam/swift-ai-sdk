import AI
import Foundation

func example_speech() async throws {
    let speech = try await generateSpeech(
        model: OpenAISpeechModel("gpt-4o-mini-tts"),
        text: "The quick brown fox jumped over the lazy dog.",
        voice: "alloy"
    )
    try speech.audio.write(to: URL(fileURLWithPath: "/tmp/hello.mp3"))
}

func example_transcription() async throws {
    let audio = try Data(contentsOf: URL(fileURLWithPath: "/tmp/hello.mp3"))
    let transcript = try await transcribe(
        model: OpenAITranscriptionModel("whisper-1"),
        audio: audio,
        mediaType: "audio/mpeg"
    )
    print(transcript.text)
    for segment in transcript.segments {
        print("\(segment.startSecond)s to \(segment.endSecond)s:", segment.text)
    }
}
