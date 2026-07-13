import XCTest
@testable import AI

final class GoogleVertexTests: XCTestCase {

    func testBearerModeURLAndAuthHeader() throws {
        let model = GoogleVertexModel(
            "gemini-2.5-flash",
            project: "proj", location: "us-central1", accessToken: "tok"
        )
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/proj/locations/us-central1/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "x-goog-api-key"))
    }

    func testLocationToHostTable() throws {
        let cases: [(location: String, host: String)] = [
            ("global", "aiplatform.googleapis.com"),
            ("eu", "aiplatform.eu.rep.googleapis.com"),
            ("us", "aiplatform.us.rep.googleapis.com"),
            ("asia-northeast1", "asia-northeast1-aiplatform.googleapis.com")
        ]
        for testCase in cases {
            let model = GoogleVertexModel(
                "gemini-2.5-flash",
                project: "proj", location: testCase.location, accessToken: "tok"
            )
            XCTAssertEqual(
                try model.resolvedBaseURL(),
                "https://\(testCase.host)/v1beta1/projects/proj/locations/\(testCase.location)/publishers/google",
                "host drifted for location \(testCase.location)"
            )
        }
    }

    func testExpressModePutsKeyInHeaderNotQuery() throws {
        let model = GoogleVertexModel("gemini-2.5-flash", apiKey: "k")
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testExpressModeWinsOverBearerToken() throws {
        let model = GoogleVertexModel("gemini-2.5-flash", apiKey: "k", accessToken: "tok")
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try model.resolvedBaseURL(), "https://aiplatform.googleapis.com/v1/publishers/google")
    }

    func testTunedEndpointModelsSkipPublishersSegment() throws {
        let model = GoogleVertexModel(
            "endpoints/123",
            project: "proj", location: "us-central1", accessToken: "tok"
        )
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/proj/locations/us-central1/endpoints/123:streamGenerateContent?alt=sse"
        )
    }

    func testTunedModelRejectsExpressMode() {
        let model = GoogleVertexModel("endpoints/123", apiKey: "k")
        XCTAssertThrowsError(
            try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        )
    }

    func testBearerModeWithoutProjectThrows() {
        let model = GoogleVertexModel(
            "gemini-2.5-flash",
            project: "", location: "us-central1", accessToken: "tok"
        )
        XCTAssertThrowsError(
            try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        )
    }

    func testBaseURLOverrideReplacesDerivedBaseAndDropsTrailingSlash() throws {
        let model = GoogleVertexModel(
            "gemini-2.5-flash",
            apiKey: "k",
            baseURL: URL(string: "https://gateway.example.com/vertex/")!
        )
        XCTAssertEqual(try model.resolvedBaseURL(), "https://gateway.example.com/vertex")
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://gateway.example.com/vertex/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
    }

    func testRequestBodyIsTheSharedGeminiMapping() throws {
        let model = GoogleVertexModel("gemini-2.5-flash", apiKey: "k")
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [
            .system("Be terse."), .user("Hi")
        ]))
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody ?? Data())
        let firstContent = body["contents"]?.arrayValue?.first
        XCTAssertEqual(firstContent?["role"], "user")
        XCTAssertEqual(firstContent?["parts"]?.arrayValue?.first?["text"], "Hi")
        XCTAssertEqual(
            body["systemInstruction"]?["parts"]?.arrayValue?.first?["text"],
            "Be terse."
        )
    }

    func testProviderNameAndModelID() {
        let model = GoogleVertexModel("gemini-2.5-flash", apiKey: "k")
        XCTAssertEqual(model.provider, "google.vertex")
        XCTAssertEqual(model.modelID, "gemini-2.5-flash")
    }
}
