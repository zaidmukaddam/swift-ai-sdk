import XCTest
@testable import AI

final class MultimodalTests: XCTestCase {

    private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    private func imageMessage() -> [Message] {
        [Message(role: .user, content: [
            .text("What is in this picture?"),
            .image(ImageContent(data: pngBytes))
        ])]
    }

    func testMediaTypeDetectionFromBytes() {
        XCTAssertEqual(ImageContent(data: pngBytes).resolvedMediaType, "image/png")
        XCTAssertEqual(
            ImageContent(data: Data([0xFF, 0xD8, 0xFF, 0xE0])).resolvedMediaType, "image/jpeg"
        )
        XCTAssertEqual(ImageContent(data: Data([0x00, 0x01])).resolvedMediaType, "image/jpeg")
        XCTAssertEqual(
            ImageContent(data: Data([0x00]), mediaType: "image/webp").resolvedMediaType,
            "image/webp"
        )
    }

    func testChatWireBuildsContentArrayForImages() {
        let body = OpenAIChatModel.requestBody(
            for: LanguageModelRequest(messages: imageMessage()), modelID: "gpt-4o"
        )
        let content = body["messages"]?.arrayValue?.first?["content"]
        let parts = content?.arrayValue
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0]["type"], "text")
        XCTAssertEqual(parts?[1]["type"], "image_url")
        let url = parts?[1]["image_url"]?["url"]?.stringValue
        XCTAssertTrue(url?.hasPrefix("data:image/png;base64,") == true)
    }

    func testChatWireKeepsPlainStringForTextOnly() {
        let body = OpenAIChatModel.requestBody(
            for: LanguageModelRequest(messages: [.user("hi")]), modelID: "gpt-4o"
        )
        XCTAssertEqual(body["messages"]?.arrayValue?.first?["content"], "hi")
    }

    func testAnthropicBase64SourceBlock() {
        let body = AnthropicModel.requestBody(
            for: LanguageModelRequest(messages: imageMessage()), modelID: "claude-sonnet-5"
        )
        let blocks = body["messages"]?.arrayValue?.first?["content"]?.arrayValue
        let image = blocks?.first { $0["type"]?.stringValue == "image" }
        XCTAssertEqual(image?["source"]?["type"], "base64")
        XCTAssertEqual(image?["source"]?["media_type"], "image/png")
        XCTAssertNotNil(image?["source"]?["data"]?.stringValue)
    }

    func testGeminiInlineDataAndFileData() {
        let inline = GoogleModel.requestBody(
            for: LanguageModelRequest(messages: imageMessage())
        )
        let parts = inline["contents"]?.arrayValue?.first?["parts"]?.arrayValue
        let inlineData = parts?.first { $0["inlineData"] != nil }?["inlineData"]
        XCTAssertEqual(inlineData?["mimeType"], "image/png")
        XCTAssertNotNil(inlineData?["data"]?.stringValue)

        let byURL = GoogleModel.requestBody(
            for: LanguageModelRequest(messages: [Message(role: .user, content: [
                .image(ImageContent(url: URL(string: "https://example.com/cat.png")!,
                                    mediaType: "image/png"))
            ])])
        )
        let fileData = byURL["contents"]?.arrayValue?.first?["parts"]?.arrayValue?
            .first { $0["fileData"] != nil }?["fileData"]
        XCTAssertEqual(fileData?["fileUri"], "https://example.com/cat.png")
        XCTAssertEqual(fileData?["mimeType"], "image/png")
    }

    func testBedrockImageAndDocumentBlocks() {
        let request = LanguageModelRequest(messages: [Message(role: .user, content: [
            .image(ImageContent(data: pngBytes)),
            .file(FileContent(data: Data("hello".utf8), mediaType: "application/pdf",
                              filename: "report.pdf"))
        ])])
        let body = BedrockModel.requestBody(for: request)
        let blocks = body["messages"]?.arrayValue?.first?["content"]?.arrayValue
        let image = blocks?.first { $0["image"] != nil }?["image"]
        XCTAssertEqual(image?["format"], "png")
        XCTAssertNotNil(image?["source"]?["bytes"]?.stringValue)
        let document = blocks?.first { $0["document"] != nil }?["document"]
        XCTAssertEqual(document?["format"], "pdf")
        XCTAssertEqual(document?["name"], "report.pdf")
    }

    func testCohereVisionImageParts() {
        let body = CohereModel.requestBody(
            for: LanguageModelRequest(messages: imageMessage()), modelID: "command-a-vision"
        )
        let content = body["messages"]?.arrayValue?.first?["content"]?.arrayValue
        XCTAssertEqual(content?.first?["type"], "text")
        let image = content?.first { $0["type"]?.stringValue == "image_url" }
        XCTAssertTrue(
            image?["image_url"]?["url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true
        )
    }

    func testConvertToModelMessagesMapsFileParts() {
        let dataURL = "data:image/png;base64,\(pngBytes.base64EncodedString())"
        let ui: [UIMessage] = [UIMessage(id: "u", role: .user, parts: [
            .text(TextUIPart(text: "look")),
            .file(FileUIPart(url: dataURL, mediaType: "image/png")),
            .file(FileUIPart(url: "https://example.com/doc.pdf",
                             mediaType: "application/pdf", filename: "doc.pdf"))
        ])]
        let messages = convertToModelMessages(ui)
        XCTAssertEqual(messages.count, 1)

        guard case .image(let image) = messages[0].content[1] else {
            return XCTFail("expected image part, got \(messages[0].content[1])")
        }
        XCTAssertEqual(image.data, pngBytes)

        guard case .file(let file) = messages[0].content[2] else {
            return XCTFail("expected file part, got \(messages[0].content[2])")
        }
        XCTAssertEqual(file.url?.absoluteString, "https://example.com/doc.pdf")
        XCTAssertEqual(file.filename, "doc.pdf")
    }
}
