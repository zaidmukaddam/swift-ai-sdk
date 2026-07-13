import XCTest
@testable import AI

final class GoogleModelTests: XCTestCase {

    private let model = GoogleModel("gemini-2.5-flash", apiKey: "k")

    private func body(for request: LanguageModelRequest) -> [String: JSONValue] {
        GoogleModel.requestBody(for: request).objectValue ?? [:]
    }

    func testStreamGenerateContentURLAndHeaders() throws {
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-goog-api-key"), "k")
    }

    func testMessageMappingRolesAndParts() {
        let request = LanguageModelRequest(messages: [
            .system("Be terse."),
            .user("Weather in Mumbai?"),
            Message(role: .assistant, content: [
                .toolCall(ToolCall(id: "c1", name: "weather", arguments: ["city": "Mumbai"]))
            ]),
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "c1", name: "weather", output: .number(31)))
            ])
        ])
        let body = body(for: request)

        let contents = body["contents"]?.arrayValue ?? []
        guard contents.count == 3 else {
            return XCTFail("expected 3 contents, got \(contents.count)")
        }
        XCTAssertEqual(contents.map { $0["role"]?.stringValue }, ["user", "model", "user"])

        XCTAssertEqual(contents[0]["parts"]?.arrayValue?.first?["text"], "Weather in Mumbai?")

        let functionCall = contents[1]["parts"]?.arrayValue?.first?["functionCall"]
        XCTAssertEqual(functionCall?["name"], "weather")
        XCTAssertEqual(functionCall?["args"]?["city"], "Mumbai")

        let functionResponse = contents[2]["parts"]?.arrayValue?.first?["functionResponse"]
        XCTAssertEqual(functionResponse?["name"], "weather")
        XCTAssertEqual(functionResponse?["response"]?["result"]?.intValue, 31)

        XCTAssertEqual(
            body["systemInstruction"]?["parts"]?.arrayValue?.first?["text"],
            "Be terse."
        )
    }

    func testObjectToolOutputPassesThroughUnwrapped() {
        let request = LanguageModelRequest(messages: [
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "c1", name: "weather", output: ["tempC": 31]))
            ])
        ])
        let contents = body(for: request)["contents"]?.arrayValue ?? []
        let response = contents.first?["parts"]?.arrayValue?.first?["functionResponse"]?["response"]
        XCTAssertEqual(response?["tempC"]?.intValue, 31)
        XCTAssertNil(response?["result"])
    }

    func testCleanSchemaStripsUnsupportedKeysAtEveryLevel() {
        let schema: JSONValue = [
            "$schema": "https://json-schema.org/draft-07/schema#",
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "user": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": ["name": ["type": "string"]],
                    "required": ["name"]
                ]
            ],
            "required": ["user"],
            "anyOf": [
                ["type": "string"],
                ["type": "object", "$schema": "x", "additionalProperties": false]
            ]
        ]
        let cleaned = GoogleModel.cleanSchema(schema)

        XCTAssertNil(cleaned["$schema"])
        XCTAssertNil(cleaned["additionalProperties"])
        XCTAssertEqual(cleaned["type"], "object")
        XCTAssertEqual(cleaned["required"], ["user"])

        let user = cleaned["properties"]?["user"]
        XCTAssertNil(user?["additionalProperties"])
        XCTAssertEqual(user?["required"], ["name"])
        XCTAssertEqual(user?["properties"]?["name"]?["type"], "string")

        let variant = cleaned["anyOf"]?.arrayValue?[1]
        XCTAssertNil(variant?["$schema"])
        XCTAssertNil(variant?["additionalProperties"])
        XCTAssertEqual(variant?["type"], "object")
    }

    func testJSONResponseFormatSetsGenerationConfig() {
        let request = LanguageModelRequest(
            messages: [.user("Hi")],
            responseFormat: .json(schema: [
                "type": "object",
                "additionalProperties": false,
                "properties": ["name": ["type": "string"]]
            ])
        )
        let config = body(for: request)["generationConfig"]
        XCTAssertEqual(config?["responseMimeType"], "application/json")
        XCTAssertEqual(config?["responseSchema"]?["type"], "object")
        XCTAssertNil(config?["responseSchema"]?["additionalProperties"])
    }

    func testMapFinishReasonTable() {
        let cases: [(raw: String?, hadToolCalls: Bool, expected: FinishReason)] = [
            ("STOP", false, .stop),
            ("STOP", true, .toolCalls),
            (nil, false, .stop),
            (nil, true, .toolCalls),
            ("MAX_TOKENS", false, .length),
            ("SAFETY", false, .contentFilter),
            ("MALFORMED_FUNCTION_CALL", false, .error),
            ("FINISH_REASON_UNSPECIFIED", false, .other)
        ]
        for testCase in cases {
            XCTAssertEqual(
                GoogleModel.mapFinishReason(testCase.raw, hadToolCalls: testCase.hadToolCalls),
                testCase.expected,
                "raw=\(testCase.raw ?? "nil") hadToolCalls=\(testCase.hadToolCalls)"
            )
        }
    }
}
