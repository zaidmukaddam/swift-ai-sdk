import AI
import Foundation

extension XAIExamples {
    static func image() async throws {
        let result = try await generateImage(
            model: XaiImageModel("grok-2-image"),
            prompt: "A retro travel poster for Mars"
        )
        print(result.image.count)
    }

    static func speechAndTranscription() async throws {
        let spoken = try await generateSpeech(
            model: XaiSpeechModel("grok-tts"),
            text: "Welcome aboard.",
            voice: "eve"
        )
        print(spoken.mediaType)

        let audio = try exampleData(at: "/tmp/example.mp3")
        let text = try await transcribe(
            model: XaiTranscriptionModel("grok-stt"),
            audio: audio,
            mediaType: "audio/mpeg"
        )
        print(text.text)
    }

    static func deferredCompletion() async throws {
        let model = XaiModel.chat("grok-4.5")
        let done = try await model.submitDeferredCompletion(
            LanguageModelRequest(
                messages: [.user("Summarize the news in one line.")],
                maxOutputTokens: 128
            )
        )
        print(done.text, done.usage.outputTokens)
    }

    static func files() async throws {
        let files = XaiFilesClient()
        let uploaded = try await files.upload(
            Data("notes".utf8), filename: "notes.txt", mediaType: "text/plain"
        )
        print(uploaded.id)
        try await files.delete(uploaded.id)
    }
}
