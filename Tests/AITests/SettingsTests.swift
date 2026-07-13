import XCTest
@testable import AI

final class SettingsTests: XCTestCase {

    private var request: LanguageModelRequest {
        LanguageModelRequest(
            messages: [.user("hi")],
            topK: 40, presencePenalty: 0.5, frequencyPenalty: 0.25, seed: 42
        )
    }

    func testChatWireMapsPenaltiesAndSeedButNotTopK() {
        let body = OpenAIChatModel.requestBody(for: request, modelID: "gpt-4o")
        XCTAssertEqual(body["presence_penalty"], 0.5)
        XCTAssertEqual(body["frequency_penalty"], 0.25)
        XCTAssertEqual(body["seed"]?.intValue, 42)
        XCTAssertNil(body["top_k"])
    }

    func testAnthropicMapsTopKOnly() {
        let body = AnthropicModel.requestBody(for: request, modelID: "claude-sonnet-5")
        XCTAssertEqual(body["top_k"]?.intValue, 40)
        XCTAssertNil(body["presence_penalty"])
        XCTAssertNil(body["seed"])
    }

    func testGeminiMapsAllFourIntoGenerationConfig() {
        let body = GoogleModel.requestBody(for: request)
        let config = body["generationConfig"]
        XCTAssertEqual(config?["topK"]?.intValue, 40)
        XCTAssertEqual(config?["presencePenalty"], 0.5)
        XCTAssertEqual(config?["frequencyPenalty"], 0.25)
        XCTAssertEqual(config?["seed"]?.intValue, 42)
    }

    func testCohereMapsKPenaltiesAndSeed() {
        let body = CohereModel.requestBody(for: request, modelID: "command-r")
        XCTAssertEqual(body["k"]?.intValue, 40)
        XCTAssertEqual(body["presence_penalty"], 0.5)
        XCTAssertEqual(body["frequency_penalty"], 0.25)
        XCTAssertEqual(body["seed"]?.intValue, 42)
    }

    func testBedrockPutsTopKInAdditionalModelRequestFields() {
        let body = BedrockModel.requestBody(for: request)
        XCTAssertEqual(body["additionalModelRequestFields"]?["top_k"]?.intValue, 40)
        XCTAssertNil(body["inferenceConfig"]?["topK"])
    }

    func testResponsesWiresMapSeedOnly() {
        let xai = XaiModel.responsesBody(for: request, modelID: "grok-4")
        XCTAssertEqual(xai["seed"]?.intValue, 42)
        XCTAssertNil(xai["top_k"])
        XCTAssertNil(xai["presence_penalty"])
    }

    private func scripted(_ parts: [StreamPart]) -> MockModel {
        MockModel(scripts: [parts])
    }

    func testOnFinishFiresWithAssembledResult() async throws {
        let recorder = ResultRecorder()
        _ = try await generateText(
            model: scripted([.textDelta("hi"), .finish(reason: .stop, usage: .init())]),
            prompt: "x",
            onFinish: { result in await recorder.record(result.text) }
        )
        let recorded = await recorder.values
        XCTAssertEqual(recorded, ["hi"])
    }

    func testOnErrorFiresBeforeThrowing() async {
        struct Exploding: LanguageModel {
            let provider = "boom"; let modelID = "b"
            func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
                throw AIError.http(status: 401, body: "no")
            }
        }
        let recorder = ResultRecorder()
        do {
            _ = try await generateText(
                model: Exploding(), prompt: "x",
                onError: { error in await recorder.record("\(error)") },
                maxRetries: 0
            )
            XCTFail("expected throw")
        } catch {
            let recorded = await recorder.values
            XCTAssertEqual(recorded.count, 1)
        }
    }

    func testStreamTextOnFinishFiresAfterDrain() async throws {
        let recorder = ResultRecorder()
        let result = streamText(
            model: scripted([.textDelta("a"), .finish(reason: .stop, usage: .init())]),
            prompt: "x",
            onFinish: { result in await recorder.record(result.text) }
        )
        for try await _ in result.textStream {}
        try await Task.sleep(nanoseconds: 50_000_000)
        let recorded = await recorder.values
        XCTAssertEqual(recorded, ["a"])
    }
}

private actor ResultRecorder {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
