import XCTest
@testable import AI

final class AzureOpenAITests: XCTestCase {

    func testResourceBasedURLUsesUnifiedV1Path() {
        let azure = AzureOpenAIProvider(resourceName: "myres", apiKey: "k")
        XCTAssertEqual(
            azure("gpt-4o-dep").requestURL(path: "chat/completions").absoluteString,
            "https://myres.openai.azure.com/openai/v1/chat/completions?api-version=v1"
        )
    }

    func testAzureHostedBaseURLAppendsV1AndAPIVersion() {
        let azure = AzureOpenAIProvider(
            apiKey: "k",
            baseURL: URL(string: "https://myres.openai.azure.com/openai")!
        )
        XCTAssertEqual(
            azure("dep").requestURL(path: "chat/completions").absoluteString,
            "https://myres.openai.azure.com/openai/v1/chat/completions?api-version=v1"
        )
    }

    func testCustomGatewayBaseURLSkipsV1AndAPIVersion() {
        let azure = AzureOpenAIProvider(
            apiKey: "k",
            baseURL: URL(string: "https://gw.example.com/azure")!
        )
        XCTAssertEqual(
            azure("dep").requestURL(path: "chat/completions").absoluteString,
            "https://gw.example.com/azure/chat/completions"
        )
    }

    func testTrailingSlashOnBaseURLIsStripped() {
        let azure = AzureOpenAIProvider(
            apiKey: "k",
            baseURL: URL(string: "https://gw.example.com/azure/")!
        )
        XCTAssertEqual(
            azure("dep").requestURL(path: "chat/completions").absoluteString,
            "https://gw.example.com/azure/chat/completions"
        )
    }

    func testDeploymentBasedURLsPutTheDeploymentInThePath() {
        let azure = AzureOpenAIProvider(
            resourceName: "myres",
            apiKey: "k",
            apiVersion: "2024-10-21",
            useDeploymentBasedUrls: true
        )
        XCTAssertEqual(
            azure("gpt-4o-dep").requestURL(path: "chat/completions").absoluteString,
            "https://myres.openai.azure.com/openai/deployments/gpt-4o-dep/chat/completions?api-version=2024-10-21"
        )
    }

    func testDeploymentModeOnAGatewayStillSendsAPIVersion() {
        let azure = AzureOpenAIProvider(
            apiKey: "k",
            baseURL: URL(string: "https://gw.example.com/azure")!,
            useDeploymentBasedUrls: true
        )
        XCTAssertEqual(
            azure("dep").requestURL(path: "chat/completions").absoluteString,
            "https://gw.example.com/azure/deployments/dep/chat/completions?api-version=v1"
        )
    }

    func testAuthRidesTheAPIKeyHeaderNotBearer() {
        let azure = AzureOpenAIProvider(resourceName: "r", apiKey: "azure-key")
        XCTAssertEqual(azure.engineHeaders["api-key"], "azure-key")
        XCTAssertNil(azure.engineHeaders["Authorization"])
    }

    func testNoAPIKeyHeaderWithoutAKey() {
        let azure = AzureOpenAIProvider(resourceName: "r", apiKey: "")
        XCTAssertNil(azure.engineHeaders["api-key"])
    }

    func testUserHeadersMergeOverTheAuthHeader() {
        let azure = AzureOpenAIProvider(
            resourceName: "r",
            apiKey: "k",
            headers: ["x-team": "ios", "api-key": "override"]
        )
        XCTAssertEqual(azure.engineHeaders["x-team"], "ios")
        XCTAssertEqual(azure.engineHeaders["api-key"], "override")
    }

    func testVendedModelCarriesProviderNameAndDeploymentID() {
        let model = AzureOpenAIProvider(resourceName: "r", apiKey: "k")("gpt-4o-dep")
        XCTAssertEqual(model.provider, "azure")
        XCTAssertEqual(model.modelID, "gpt-4o-dep")
    }

    func testProviderVendsEmbeddingModels() {
        let embed = AzureOpenAIProvider(resourceName: "r", apiKey: "k")
            .textEmbeddingModel("embedding-dep")
        XCTAssertEqual(embed.provider, "azure")
        XCTAssertEqual(embed.modelID, "embedding-dep")
    }
}
