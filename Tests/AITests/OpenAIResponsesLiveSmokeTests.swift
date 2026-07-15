import XCTest
import AI

final class OpenAIResponsesLiveSmokeTests: XCTestCase {

    private func requireKey() throws {
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        if key.isEmpty {
            throw XCTSkip("set OPENAI_API_KEY to run the OpenAI Responses live smoke tests")
        }
    }

    func testCountInputTokens() async throws {
        try requireKey()
        let client = OpenAIResponsesClient()
        let count = try await client.countInputTokens(
            for: LanguageModelRequest(
                messages: [.user("Count the tokens in this short sentence.")],
                maxOutputTokens: 16
            ),
            modelID: "gpt-5.6"
        )
        XCTAssertGreaterThan(count, 0)
    }
}
