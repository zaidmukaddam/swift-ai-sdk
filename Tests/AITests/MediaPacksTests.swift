import XCTest
@testable import AI

final class MediaPacksTests: XCTestCase {

    private let audio = Data("fake-audio".utf8)

    func testElevenLabsSpeechWire() throws {
        let model = ElevenLabsSpeechModel("eleven_multilingual_v2", apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(
            text: "Hello", voice: "voice-1", outputFormat: "mp3"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.elevenlabs.io/v1/text-to-speech/voice-1?output_format=mp3_44100_128"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "xi-api-key"), "k")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["model_id"], "eleven_multilingual_v2")
        XCTAssertEqual(body["text"], "Hello")
    }

    func testLMNTSpeechWire() throws {
        let model = LMNTSpeechModel("aurora", apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(text: "Hi"))
        XCTAssertEqual(
            urlRequest.url?.absoluteString, "https://api.lmnt.com/v1/ai/speech/bytes"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "k")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["voice"], "ava")
        XCTAssertEqual(body["model"], "aurora")
    }

    func testHumeSpeechWire() throws {
        let model = HumeSpeechModel(apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(
            text: "Hi", voice: "v-9", instructions: "calm and slow"
        ))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.hume.ai/v0/tts/file")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Hume-Api-Key"), "k")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        let utterance = body["utterances"]?.arrayValue?.first
        XCTAssertEqual(utterance?["text"], "Hi")
        XCTAssertEqual(utterance?["voice"]?["id"], "v-9")
        XCTAssertEqual(utterance?["description"], "calm and slow")
    }

    func testDeepgramSpeechWire() throws {
        let model = DeepgramSpeechModel("aura-2-thalia-en", apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(text: "Hi"))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.deepgram.com/v1/speak?model=aura-2-thalia-en"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Token k")
    }

    func testDeepgramTranscriptionWire() {
        let model = DeepgramTranscriptionModel("nova-3", apiKey: "k")
        let urlRequest = model.buildURLRequest(TranscriptionModelRequest(
            audio: audio, mediaType: "audio/mpeg"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Token k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "content-type"), "audio/mpeg")
        XCTAssertEqual(urlRequest.httpBody, audio)
    }

    func testSarvamSpeechWire() throws {
        let model = SarvamSpeechModel("bulbul:v3", apiKey: "k", targetLanguage: "hi-IN")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(
            text: "namaste", voice: "anushka", speed: 1.2, outputFormat: "mp3"
        ))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.sarvam.ai/text-to-speech")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "api-subscription-key"), "k")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["model"], "bulbul:v3")
        XCTAssertEqual(body["text"], "namaste")
        XCTAssertEqual(body["target_language_code"], "hi-IN")
        XCTAssertEqual(body["speaker"], "anushka")
        XCTAssertEqual(body["pace"], 1.2)
        XCTAssertEqual(body["output_audio_codec"], "mp3")
    }

    func testSarvamSpeechTargetLanguageOverrideViaProviderOptions() throws {
        let model = SarvamSpeechModel(apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(
            text: "hi", providerOptions: ["target_language_code": "ta-IN"]
        ))
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["target_language_code"], "ta-IN")
    }

    func testSarvamSpeechMediaTypeMapping() {
        XCTAssertEqual(SarvamSpeechModel.mediaType(for: "mp3"), "audio/mpeg")
        XCTAssertEqual(SarvamSpeechModel.mediaType(for: "opus"), "audio/opus")
        XCTAssertEqual(SarvamSpeechModel.mediaType(for: nil), "audio/wav")
        XCTAssertEqual(SarvamSpeechModel.mediaType(for: "linear16"), "audio/wav")
    }

    func testSarvamTranscriptionIsMultipart() {
        let model = SarvamTranscriptionModel("saaras:v3", apiKey: "k")
        let urlRequest = model.buildURLRequest(TranscriptionModelRequest(
            audio: audio, mediaType: "audio/wav",
            providerOptions: ["language_code": "hi-IN", "mode": "transcribe"]
        ))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.sarvam.ai/speech-to-text")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "api-subscription-key"), "k")
        let body = String(decoding: urlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\""))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("saaras:v3"))
        XCTAssertTrue(body.contains("name=\"language_code\""))
        XCTAssertTrue(body.contains("name=\"mode\""))
    }

    func testSarvamChatFactory() {
        let sarvam = OpenAICompatibleProvider.sarvam(apiKey: "k")
        XCTAssertEqual(sarvam.name, "sarvam")
        XCTAssertEqual(sarvam.baseURL.absoluteString, "https://api.sarvam.ai/v1")
        let model = sarvam("sarvam-105b")
        XCTAssertEqual(model.provider, "sarvam")
        XCTAssertEqual(model.modelID, "sarvam-105b")
    }

    func testElevenLabsTranscriptionIsMultipart() {
        let model = ElevenLabsTranscriptionModel(apiKey: "k")
        let urlRequest = model.buildURLRequest(TranscriptionModelRequest(
            audio: audio, mediaType: "audio/mpeg"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text"
        )
        let body = String(decoding: urlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\""))
        XCTAssertTrue(body.contains("name=\"model_id\""))
    }

    func testAssemblyAIPollStates() throws {
        XCTAssertNil(try AssemblyAITranscriptionModel.resolvePoll(["status": "processing"]))

        let done = try AssemblyAITranscriptionModel.resolvePoll([
            "status": "completed",
            "text": "hello world",
            "language_code": "en",
            "audio_duration": 2.5,
            "words": [["text": "hello", "start": 100, "end": 500],
                      ["text": "world", "start": 600, "end": 1100]]
        ])
        XCTAssertEqual(done?.text, "hello world")
        XCTAssertEqual(done?.segments.first?.startSecond ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(done?.durationInSeconds ?? 0, 2.5, accuracy: 1e-9)

        XCTAssertThrowsError(try AssemblyAITranscriptionModel.resolvePoll(
            ["status": "error", "error": "bad audio"]
        ))
    }

    func testRevAITranscriptParsing() throws {
        let response = try RevAITranscriptionModel.parseTranscript([
            "monologues": [[
                "elements": [
                    ["type": "text", "value": "Hello", "ts": 0.5, "end_ts": 0.9],
                    ["type": "punct", "value": " "],
                    ["type": "text", "value": "there", "ts": 1.0, "end_ts": 1.4]
                ]
            ]]
        ])
        XCTAssertEqual(response.text, "Hello there")
        XCTAssertEqual(response.segments.count, 2)
        XCTAssertEqual(response.segments[1].startSecond, 1.0, accuracy: 1e-9)
    }

    func testGladiaPollStates() throws {
        XCTAssertNil(try GladiaTranscriptionModel.resolvePoll(["status": "processing"]))
        let done = try GladiaTranscriptionModel.resolvePoll([
            "status": "done",
            "result": [
                "transcription": [
                    "full_transcript": "bonjour",
                    "utterances": [["text": "bonjour", "start": 0.2, "end": 0.8, "language": "fr"]]
                ],
                "metadata": ["audio_duration": 1.1]
            ]
        ])
        XCTAssertEqual(done?.text, "bonjour")
        XCTAssertEqual(done?.language, "fr")
        XCTAssertThrowsError(try GladiaTranscriptionModel.resolvePoll(["status": "error"]))
    }

    func testFalImageWire() throws {
        let model = FalImageModel("fal-ai/flux/schnell", apiKey: "k")
        let urlRequest = try model.buildURLRequest(ImageModelRequest(
            prompt: "a fox", n: 2, size: "1024x768"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString, "https://fal.run/fal-ai/flux/schnell"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Key k")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["num_images"]?.intValue, 2)
        XCTAssertEqual(body["image_size"]?["width"]?.intValue, 1024)
    }

    func testLumaPollStates() throws {
        let pending = try LumaGenerationEngine.resolvePoll(["state": "dreaming"]) {
            $0["assets"]?["image"]?.stringValue
        }
        XCTAssertNil(pending)

        let done = try LumaGenerationEngine.resolvePoll([
            "state": "completed",
            "assets": ["image": "https://cdn.luma.ai/out.png"]
        ]) { $0["assets"]?["image"]?.stringValue }
        XCTAssertEqual(done?.absoluteString, "https://cdn.luma.ai/out.png")

        XCTAssertThrowsError(try LumaGenerationEngine.resolvePoll(
            ["state": "failed", "failure_reason": "nsfw"]
        ) { _ in nil })
    }

    func testReplicateWireAndVersionRouting() throws {
        let model = ReplicateImageModel("black-forest-labs/flux-schnell", apiKey: "k")
        let urlRequest = try model.buildURLRequest(ImageModelRequest(prompt: "a fox"))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Prefer"), "wait")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["input"]?["prompt"], "a fox")

        let versioned = ReplicateImageModel("owner/name:abc123", apiKey: "k")
        let versionedRequest = try versioned.buildURLRequest(ImageModelRequest(prompt: "x"))
        XCTAssertEqual(
            versionedRequest.url?.absoluteString, "https://api.replicate.com/v1/predictions"
        )
        let versionedBody = try JSONDecoder().decode(
            JSONValue.self, from: versionedRequest.httpBody!
        )
        XCTAssertEqual(versionedBody["version"], "abc123")
    }
}
