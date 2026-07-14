import XCTest
@testable import AI

final class CompatFamilyTests: XCTestCase {

    func testFamilyModelsCarryProviderNames() {
        XCTAssertEqual(DeepInfraModel("m", apiKey: "k").provider, "deepinfra")
        XCTAssertEqual(BasetenModel("m", apiKey: "k").provider, "baseten")
        XCTAssertEqual(VercelModel("m", apiKey: "k").provider, "vercel")
        XCTAssertEqual(AIGatewayModel("m", apiKey: "k").provider, "gateway")
    }

    func testDeepInfraChatURLKeepsTheOpenAISegment() {
        let model = DeepInfraModel("m", apiKey: "k")
        XCTAssertEqual(model.provider, "deepinfra")
        XCTAssertEqual(
            model.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.deepinfra.com/v1/openai/chat/completions"
        )
    }

    func testFamilyBaseURLsMatchTheAISDK() {
        XCTAssertEqual(
            BasetenModel("m", apiKey: "k").engine.requestURL(path: "chat/completions").absoluteString,
            "https://inference.baseten.co/v1/chat/completions"
        )
        XCTAssertEqual(
            VercelModel("m", apiKey: "k").engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.v0.dev/v1/chat/completions"
        )
    }

    func testGatewayModelUsesTheOpenAICompatibleSurface() {
        let model = AIGatewayModel("anthropic/claude-sonnet-5", apiKey: "k")
        XCTAssertEqual(model.provider, "gateway")
        XCTAssertEqual(model.modelID, "anthropic/claude-sonnet-5")
        XCTAssertEqual(
            model.engine.requestURL(path: "chat/completions").absoluteString,
            "https://ai-gateway.vercel.sh/v1/chat/completions"
        )
    }

    /// Each first-class pack's API-key env var is hand-copied from its documented name;
    /// this pins every one so a future edit (like the Vercel/VERCEL_API_KEY regression
    /// this test was added to catch) fails loudly instead of silently 401ing.
    func testFirstClassCompatibleModelsReadTheDocumentedEnvironmentVariable() {
        let expected: [(String?, String)] = [
            (AIGatewayModel.configuration.apiKeyEnvironmentVariable, "AI_GATEWAY_API_KEY"),
            (BasetenModel.configuration.apiKeyEnvironmentVariable, "BASETEN_API_KEY"),
            (CerebrasModel.configuration.apiKeyEnvironmentVariable, "CEREBRAS_API_KEY"),
            (DeepInfraModel.configuration.apiKeyEnvironmentVariable, "DEEPINFRA_API_KEY"),
            (FireworksModel.configuration.apiKeyEnvironmentVariable, "FIREWORKS_API_KEY"),
            (OpenRouterModel.configuration.apiKeyEnvironmentVariable, "OPENROUTER_API_KEY"),
            (SarvamModel.configuration.apiKeyEnvironmentVariable, "SARVAM_API_KEY"),
            (TogetherAIModel.configuration.apiKeyEnvironmentVariable, "TOGETHER_API_KEY"),
            (VercelModel.configuration.apiKeyEnvironmentVariable, "VERCEL_API_KEY")
        ]
        for (actual, expectedName) in expected {
            XCTAssertEqual(actual, expectedName)
        }
        XCTAssertNil(OllamaModel.configuration.apiKeyEnvironmentVariable)
        XCTAssertNil(LMStudioModel.configuration.apiKeyEnvironmentVariable)
    }

    func testDeprecatedOllamaAndLMStudioShimDefaultsMatchTheirModelPack() {
        XCTAssertEqual(
            OpenAICompatibleProvider.ollama().baseURL, OllamaModel.configuration.baseURL
        )
        XCTAssertEqual(
            OpenAICompatibleProvider.lmStudio().baseURL, LMStudioModel.configuration.baseURL
        )
    }

    func testQueryParamsForwardThroughFirstClassModelPacks() {
        let model = TogetherAIModel("m", apiKey: "k", queryParams: ["api-version": "2026-01-01"])
        XCTAssertEqual(
            model.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.together.xyz/v1/chat/completions?api-version=2026-01-01"
        )
    }

    func testFirstClassModelPacksVendEmbeddingModels() {
        let together = TogetherAIEmbeddingModel("BAAI/bge-large-en-v1.5", apiKey: "k")
        XCTAssertEqual(together.provider, "togetherai")
        XCTAssertEqual(together.modelID, "BAAI/bge-large-en-v1.5")

        let deepInfra = DeepInfraEmbeddingModel("BAAI/bge-base-en-v1.5", apiKey: "k")
        XCTAssertEqual(deepInfra.provider, "deepinfra")

        let baseten = BasetenEmbeddingModel("m", apiKey: "k")
        XCTAssertEqual(baseten.provider, "baseten")
    }
}
