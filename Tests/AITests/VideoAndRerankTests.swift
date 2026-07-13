import XCTest
@testable import AI

final class VideoAndRerankTests: XCTestCase {

    func testCreateRequestBodyAndURL() throws {
        let model = XaiVideoModel("grok-video-1", apiKey: "k")
        let urlRequest = try model.buildCreateRequest(VideoModelRequest(
            prompt: "a paper boat", aspectRatio: "16:9", duration: 6
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString, "https://api.x.ai/v1/videos/generations"
        )
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["model"], "grok-video-1")
        XCTAssertEqual(body["prompt"], "a paper boat")
        XCTAssertEqual(body["duration"]?.intValue, 6)
        XCTAssertEqual(body["aspect_ratio"], "16:9")
    }

    func testStartImageBecomesDataURL() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let model = XaiVideoModel("grok-video-1", apiKey: "k")
        let urlRequest = try model.buildCreateRequest(VideoModelRequest(
            prompt: "animate this", image: ImageContent(data: png)
        ))
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertTrue(
            body["image"]?["url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true
        )
    }

    func testStatusRequestTargetsJobPath() {
        let model = XaiVideoModel("grok-video-1", apiKey: "k")
        let urlRequest = model.buildStatusRequest(requestID: "req-9")
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.x.ai/v1/videos/req-9")
        XCTAssertEqual(urlRequest.httpMethod, "GET")
    }

    func testPollStateInterpretation() throws {
        XCTAssertNil(try XaiVideoModel.resolvePoll(["status": "pending"]))

        let done = try XaiVideoModel.resolvePoll(
            ["status": "done", "video": ["url": "https://cdn.x.ai/v.mp4"]]
        )
        XCTAssertEqual(done?.urls.first?.absoluteString, "https://cdn.x.ai/v.mp4")

        XCTAssertNotNil(try XaiVideoModel.resolvePoll(
            ["video": ["url": "https://cdn.x.ai/v.mp4"]]
        ))

        XCTAssertThrowsError(try XaiVideoModel.resolvePoll(["status": "failed"]))
        XCTAssertThrowsError(try XaiVideoModel.resolvePoll(["status": "expired"]))
        XCTAssertThrowsError(try XaiVideoModel.resolvePoll(
            ["status": "done",
             "video": ["url": "https://x", "respect_moderation": false]]
        ))
    }

    func testGenerateVideoAgainstMock() async throws {
        struct MockVideo: VideoModel {
            let provider = "mock"; let modelID = "mock-video"
            func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse {
                VideoModelResponse(urls: [URL(string: "https://example.com/out.mp4")!])
            }
        }
        let result = try await generateVideo(model: MockVideo(), prompt: "x")
        XCTAssertEqual(result.urls.count, 1)
        XCTAssertEqual(result.mediaType, "video/mp4")
        XCTAssertNil(result.video)
    }

    func testRerankRequestBody() throws {
        let model = CohereRerankingModel("rerank-v3.5", apiKey: "k")
        let urlRequest = try model.buildURLRequest(
            query: "capital of the US", documents: ["Carson City", "Washington, D.C."], topN: 1
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.cohere.com/v2/rerank")
        let body = try JSONDecoder().decode(JSONValue.self, from: urlRequest.httpBody!)
        XCTAssertEqual(body["model"], "rerank-v3.5")
        XCTAssertEqual(body["query"], "capital of the US")
        XCTAssertEqual(body["documents"]?.arrayValue?.count, 2)
        XCTAssertEqual(body["top_n"]?.intValue, 1)
    }

    func testRerankMapsIndicesBackToDocuments() async throws {
        struct MockReranker: RerankingModel {
            let provider = "mock"; let modelID = "mock-rerank"
            func rerank(query: String, documents: [String], topN: Int?) async throws -> [RankedDocumentIndex] {
                [RankedDocumentIndex(index: 2, relevanceScore: 0.98),
                 RankedDocumentIndex(index: 0, relevanceScore: 0.15)]
            }
        }
        let result = try await rerank(
            model: MockReranker(), query: "q", documents: ["a", "b", "c"]
        )
        XCTAssertEqual(result.rankedDocuments.map(\.document), ["c", "a"])
        XCTAssertEqual(result.rankedDocuments.first?.relevanceScore ?? 0, 0.98, accuracy: 1e-9)
    }

    func testRerankWithEmptyDocumentsSkipsTheCall() async throws {
        struct ExplodingReranker: RerankingModel {
            let provider = "boom"; let modelID = "b"
            func rerank(query: String, documents: [String], topN: Int?) async throws -> [RankedDocumentIndex] {
                XCTFail("should not be called")
                return []
            }
        }
        let result = try await rerank(model: ExplodingReranker(), query: "q", documents: [])
        XCTAssertTrue(result.rankedDocuments.isEmpty)
    }
}
