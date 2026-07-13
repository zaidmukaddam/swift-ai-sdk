import XCTest
@testable import AI

final class CompatFamilyTests: XCTestCase {

    func testFamilyBaseURLsMatchTheAISDK() {
        let expected: [(OpenAICompatibleProvider, String, String)] = [
            (.deepInfra(apiKey: "k"), "deepinfra", "https://api.deepinfra.com/v1/openai"),
            (.baseten(apiKey: "k"), "baseten", "https://inference.baseten.co/v1"),
            (.vercel(apiKey: "k"), "vercel", "https://api.v0.dev/v1"),
            (.gateway(apiKey: "k"), "gateway", "https://ai-gateway.vercel.sh/v1")
        ]
        for (provider, name, url) in expected {
            XCTAssertEqual(provider.name, name)
            XCTAssertEqual(provider.baseURL.absoluteString, url, "base URL drifted for \(name)")
        }
    }

    func testDeepInfraChatURLKeepsTheOpenAISegment() {
        let model = OpenAICompatibleProvider.deepInfra(apiKey: "k")("m")
        XCTAssertEqual(model.provider, "deepinfra")
        XCTAssertEqual(
            model.requestURL(path: "chat/completions").absoluteString,
            "https://api.deepinfra.com/v1/openai/chat/completions"
        )
    }

    func testDeepInfraEmbeddingsShareTheOpenAISegment() {
        let embed = OpenAICompatibleProvider.deepInfra(apiKey: "k")
            .textEmbeddingModel("BAAI/bge-large-en-v1.5")
        XCTAssertEqual(embed.provider, "deepinfra")
        XCTAssertEqual(embed.modelID, "BAAI/bge-large-en-v1.5")
    }

    func testGatewayVendsChatOnTheOpenAICompatibleSurface() {
        let model = OpenAICompatibleProvider.gateway(apiKey: "k")("anthropic/claude-sonnet-4.5")
        XCTAssertEqual(model.provider, "gateway")
        XCTAssertEqual(model.modelID, "anthropic/claude-sonnet-4.5")
        XCTAssertEqual(
            model.requestURL(path: "chat/completions").absoluteString,
            "https://ai-gateway.vercel.sh/v1/chat/completions"
        )
    }
}
