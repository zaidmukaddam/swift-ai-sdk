import XCTest
import AI

final class XaiLiveSmokeTests: XCTestCase {

    private func requireKey() throws {
        let key = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        if key.isEmpty {
            throw XCTSkip("set XAI_API_KEY to run the xAI live smoke tests")
        }
    }

    private func skippingUnavailable<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let AIError.http(status, body) where Self.isPolicyDenial(status, body) {
            throw XCTSkip("xAI account cannot access this endpoint: \(body)")
        }
    }

    static func isPolicyDenial(_ status: Int, _ body: String) -> Bool {
        guard status == 400 || status == 403 else { return false }
        let lower = body.lowercased()
        return lower.contains("retention")
            || lower.contains("permission")
            || lower.contains("not have access")
    }

    func testFilesRoundTrip() async throws {
        try requireKey()
        try await skippingUnavailable {
            let files = XaiFilesClient()

            let payload = Data("hello from swift-ai-sdk smoke test".utf8)
            let uploaded = try await files.upload(
                payload, filename: "smoke.txt", mediaType: "text/plain"
            )
            XCTAssertFalse(uploaded.id.isEmpty)

            let fetched = try await files.get(uploaded.id)
            XCTAssertEqual(fetched.id, uploaded.id)

            let listed = try await files.list()
            XCTAssertTrue(listed.contains { $0.id == uploaded.id })

            let downloaded = try await files.download(uploaded.id)
            XCTAssertEqual(downloaded, payload)

            let deleted = try await files.delete(uploaded.id)
            XCTAssertTrue(deleted)
        }
    }

    func testChatGeneratesText() async throws {
        try requireKey()
        let result = try await generateText(
            model: XaiModel("grok-4.5"),
            prompt: "Reply with the single word: pong.",
            maxOutputTokens: 16
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    func testDeferredCompletion() async throws {
        try requireKey()
        try await skippingUnavailable {
            let model = XaiModel.chat("grok-4.5")
            let done = try await model.submitDeferredCompletion(
                LanguageModelRequest(
                    messages: [.user("Reply with the single word: pong.")],
                    maxOutputTokens: 16
                )
            )
            XCTAssertFalse(done.text.isEmpty)
            XCTAssertGreaterThan(done.usage.outputTokens, 0)
        }
    }

    func testBatchCreateAndStatus() async throws {
        try requireKey()
        try await skippingUnavailable {
            let batches = XaiBatchClient()
            let request = XaiBatchClient.Request(
                id: "req-0",
                model: "grok-4.5",
                body: .object([
                    "model": .string("grok-4.5"),
                    "messages": .array([.object([
                        "role": .string("user"),
                        "content": .string("Reply with the single word: pong.")
                    ])]),
                    "max_tokens": .number(16)
                ])
            )
            let batchID = try await batches.create(name: "swift-ai-smoke", requests: [request])
            XCTAssertFalse(batchID.isEmpty)

            let status = try await batches.get(batchID)
            XCTAssertEqual(status["batch_id"]?.stringValue, batchID)
        }
    }
}
