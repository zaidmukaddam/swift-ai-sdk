import XCTest
@testable import AI

final class MediaModelTests: XCTestCase {

    private func bodyJSON(_ urlRequest: URLRequest) throws -> [String: JSONValue] {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody ?? Data())
        return decoded.objectValue ?? [:]
    }

    func testImageRequestURLHeadersAndBody() throws {
        let model = OpenAIImageModel("dall-e-3", apiKey: "k", headers: ["x-team": "ios"])
        let urlRequest = try model.buildURLRequest(
            ImageModelRequest(prompt: "a red panda", n: 2, size: "1024x1024")
        )
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.openai.com/v1/images/generations"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-team"), "ios")

        let body = try bodyJSON(urlRequest)
        XCTAssertEqual(body["model"], "dall-e-3")
        XCTAssertEqual(body["prompt"], "a red panda")
        XCTAssertEqual(body["n"]?.intValue, 2)
        XCTAssertEqual(body["size"], "1024x1024")
        XCTAssertEqual(body["response_format"], "b64_json")
    }

    func testGptImageModelsOmitResponseFormat() throws {
        for modelID in ["gpt-image-1", "gpt-image-1.5", "chatgpt-image-latest"] {
            let model = OpenAIImageModel(modelID, apiKey: "k")
            let body = try bodyJSON(
                try model.buildURLRequest(ImageModelRequest(prompt: "x"))
            )
            XCTAssertNil(body["response_format"], "response_format leaked for \(modelID)")
        }
    }

    func testImageProviderOptionsMergeIntoBody() throws {
        let model = OpenAIImageModel("dall-e-3", apiKey: "k")
        let body = try bodyJSON(try model.buildURLRequest(ImageModelRequest(
            prompt: "x",
            providerOptions: ["openai": ["quality": "hd", "style": "vivid"]]
        )))
        XCTAssertEqual(body["quality"], "hd")
        XCTAssertEqual(body["style"], "vivid")
    }

    func testSpeechRequestURLAndBody() throws {
        let model = OpenAISpeechModel("gpt-4o-mini-tts", apiKey: "k")
        let urlRequest = try model.buildURLRequest(SpeechModelRequest(
            text: "hello", voice: "nova", instructions: "slowly", speed: 1.5, outputFormat: "wav"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.openai.com/v1/audio/speech"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")

        let body = try bodyJSON(urlRequest)
        XCTAssertEqual(body["model"], "gpt-4o-mini-tts")
        XCTAssertEqual(body["input"], "hello")
        XCTAssertEqual(body["voice"], "nova")
        XCTAssertEqual(body["response_format"], "wav")
        XCTAssertEqual(body["speed"]?.doubleValue, 1.5)
        XCTAssertEqual(body["instructions"], "slowly")
    }

    func testSpeechDefaultsAndFormatFallback() throws {
        let model = OpenAISpeechModel("tts-1", apiKey: "k")
        let defaults = try bodyJSON(try model.buildURLRequest(SpeechModelRequest(text: "x")))
        XCTAssertEqual(defaults["voice"], "alloy")
        XCTAssertEqual(defaults["response_format"], "mp3")

        let fallback = try bodyJSON(try model.buildURLRequest(
            SpeechModelRequest(text: "x", outputFormat: "ogg")
        ))
        XCTAssertEqual(fallback["response_format"], "mp3")

        XCTAssertEqual(OpenAISpeechModel.mediaType(forFormat: "mp3"), "audio/mpeg")
        XCTAssertEqual(OpenAISpeechModel.mediaType(forFormat: "wav"), "audio/wav")
    }

    func testTranscriptionRequestIsMultipart() throws {
        let model = OpenAITranscriptionModel("whisper-1", apiKey: "k")
        let urlRequest = try model.buildURLRequest(TranscriptionModelRequest(
            audio: Data([0x01, 0x02, 0x03]), mediaType: "audio/wav"
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.openai.com/v1/audio/transcriptions"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")

        let contentType = try XCTUnwrap(urlRequest.value(forHTTPHeaderField: "content-type"))
        XCTAssertTrue(
            contentType.hasPrefix("multipart/form-data; boundary="),
            "expected multipart content type, got \(contentType)"
        )

        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let body = String(decoding: urlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("--\(boundary)\r\n"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"))
        XCTAssertTrue(body.contains("Content-Type: audio/wav\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n"))
    }

    func testTranscriptionOptionsAndModelSpecificFormat() throws {
        let gpt4o = OpenAITranscriptionModel("gpt-4o-transcribe", apiKey: "k")
        let jsonBody = String(decoding: try gpt4o.buildURLRequest(
            TranscriptionModelRequest(audio: Data([0x00]), mediaType: "audio/mpeg")
        ).httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(jsonBody.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        XCTAssertTrue(jsonBody.contains("filename=\"audio.mp3\""))

        let whisper = OpenAITranscriptionModel("whisper-1", apiKey: "k")
        let optionsBody = String(decoding: try whisper.buildURLRequest(TranscriptionModelRequest(
            audio: Data([0x00]),
            mediaType: "audio/wav",
            providerOptions: ["openai": [
                "language": "en",
                "temperature": 0,
                "timestamp_granularities": ["word", "segment"]
            ]]
        )).httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(optionsBody.contains("name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertTrue(optionsBody.contains("name=\"temperature\"\r\n\r\n0\r\n"))
        XCTAssertTrue(optionsBody.contains("name=\"timestamp_granularities[]\"\r\n\r\nword\r\n"))
        XCTAssertTrue(optionsBody.contains("name=\"timestamp_granularities[]\"\r\n\r\nsegment\r\n"))
    }

    func testGenerateImageReturnsFirstAndAll() async throws {
        let result = try await generateImage(model: MockImageModel(), prompt: "cats", n: 3)
        XCTAssertEqual(result.images.count, 3)
        XCTAssertEqual(result.image, result.images[0])
        XCTAssertEqual(result.revisedPrompts, ["cats #0", "cats #1", "cats #2"])
    }

    func testGenerateImageThrowsWhenModelReturnsNothing() async throws {
        do {
            _ = try await generateImage(model: EmptyImageModel(), prompt: "x")
            XCTFail("expected decoding error")
        } catch AIError.decoding {
        }
    }

    func testGenerateSpeechHappyPath() async throws {
        let result = try await generateSpeech(
            model: MockSpeechModel(), text: "hi", voice: "alloy", outputFormat: "wav"
        )
        XCTAssertEqual(String(decoding: result.audio, as: UTF8.self), "hi|alloy|wav")
        XCTAssertEqual(result.mediaType, "audio/wav")
    }

    func testGenerateSpeechThrowsOnEmptyAudio() async throws {
        do {
            _ = try await generateSpeech(model: MockSpeechModel(), text: "")
            XCTFail("expected decoding error")
        } catch AIError.decoding {
        }
    }

    func testTranscribeHappyPath() async throws {
        let result = try await transcribe(
            model: MockTranscriptionModel(),
            audio: Data([0x01, 0x02]),
            mediaType: "audio/wav"
        )
        XCTAssertEqual(result.text, "2 bytes of audio/wav")
        XCTAssertEqual(result.segments, [
            TranscriptionSegment(text: "2 bytes", startSecond: 0, endSecond: 0.8),
            TranscriptionSegment(text: "of audio/wav", startSecond: 0.8, endSecond: 1.5)
        ])
        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.durationInSeconds, 1.5)
    }

    func testGenerateImageRetryRecoversFrom429() async throws {
        let model = FlakyImageModel(failuresBeforeSuccess: 2)
        let result = try await generateImage(model: model, prompt: "x", maxRetries: 2)
        XCTAssertEqual(result.image, Data([0xFF]))
    }

    func testGenerateImageRetryGivesUpAfterMaxRetries() async throws {
        let model = FlakyImageModel(failuresBeforeSuccess: 3)
        do {
            _ = try await generateImage(model: model, prompt: "x", maxRetries: 1)
            XCTFail("expected http error")
        } catch AIError.http(let status, _) {
            XCTAssertEqual(status, 429)
        }
    }

    func testGenerateImageNonRetryableErrorFailsFast() async throws {
        let model = FlakyImageModel(failuresBeforeSuccess: 5, status: 401)
        do {
            _ = try await generateImage(model: model, prompt: "x", maxRetries: 2)
            XCTFail("expected http error")
        } catch AIError.http(let status, _) {
            XCTAssertEqual(status, 401)
            let attempts = await model.attemptCount()
            XCTAssertEqual(attempts, 1)
        }
    }

    func testGenerateSpeechRetryRecovers() async throws {
        let model = FlakySpeechModel(failuresBeforeSuccess: 1)
        let result = try await generateSpeech(model: model, text: "x", maxRetries: 2)
        XCTAssertEqual(String(decoding: result.audio, as: UTF8.self), "recovered")
    }

    func testTranscribeRetryRecovers() async throws {
        let model = FlakyTranscriptionModel(failuresBeforeSuccess: 2)
        let result = try await transcribe(
            model: model, audio: Data([0x00]), mediaType: "audio/wav", maxRetries: 2
        )
        XCTAssertEqual(result.text, "recovered")
        let attempts = await model.attemptCount()
        XCTAssertEqual(attempts, 3)
    }
}

private actor AttemptCounter {
    var value = 0
    func increment() -> Int { value += 1; return value }
}

private struct MockImageModel: ImageModel {
    let provider = "mock"
    let modelID = "mock-image"

    func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        ImageModelResponse(
            images: (0..<request.n).map { Data([UInt8($0)]) },
            revisedPrompts: (0..<request.n).map { "\(request.prompt) #\($0)" }
        )
    }
}

private struct EmptyImageModel: ImageModel {
    let provider = "mock"
    let modelID = "mock-empty"

    func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        ImageModelResponse(images: [])
    }
}

private struct MockSpeechModel: SpeechModel {
    let provider = "mock"
    let modelID = "mock-speech"

    func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        guard !request.text.isEmpty else {
            return SpeechModelResponse(audio: Data(), mediaType: "audio/mpeg")
        }
        let echo = "\(request.text)|\(request.voice ?? "-")|\(request.outputFormat ?? "-")"
        return SpeechModelResponse(audio: Data(echo.utf8), mediaType: "audio/wav")
    }
}

private struct MockTranscriptionModel: TranscriptionModel {
    let provider = "mock"
    let modelID = "mock-transcribe"

    func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        TranscriptionModelResponse(
            text: "\(request.audio.count) bytes of \(request.mediaType)",
            segments: [
                TranscriptionSegment(
                    text: "\(request.audio.count) bytes", startSecond: 0, endSecond: 0.8
                ),
                TranscriptionSegment(
                    text: "of \(request.mediaType)", startSecond: 0.8, endSecond: 1.5
                )
            ],
            language: "en",
            durationInSeconds: 1.5
        )
    }
}

private struct FlakyImageModel: ImageModel {
    let provider = "flaky"
    let modelID = "flaky-image"
    let failuresBeforeSuccess: Int
    var status: Int = 429
    private let counter = AttemptCounter()

    func attemptCount() async -> Int { await counter.value }

    func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        let attempt = await counter.increment()
        if attempt <= failuresBeforeSuccess {
            throw AIError.http(status: status, body: "try later")
        }
        return ImageModelResponse(images: [Data([0xFF])])
    }
}

private struct FlakySpeechModel: SpeechModel {
    let provider = "flaky"
    let modelID = "flaky-speech"
    let failuresBeforeSuccess: Int
    private let counter = AttemptCounter()

    func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let attempt = await counter.increment()
        if attempt <= failuresBeforeSuccess {
            throw AIError.http(status: 429, body: "try later")
        }
        return SpeechModelResponse(audio: Data("recovered".utf8), mediaType: "audio/mpeg")
    }
}

private struct FlakyTranscriptionModel: TranscriptionModel {
    let provider = "flaky"
    let modelID = "flaky-transcribe"
    let failuresBeforeSuccess: Int
    private let counter = AttemptCounter()

    func attemptCount() async -> Int { await counter.value }

    func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        let attempt = await counter.increment()
        if attempt <= failuresBeforeSuccess {
            throw AIError.http(status: 500, body: "try later")
        }
        return TranscriptionModelResponse(text: "recovered")
    }
}
