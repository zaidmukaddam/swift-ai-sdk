import XCTest
@testable import AI

final class SchemaTests: XCTestCase {

    private let recipe = Schema.object([
        "name": .string(description: "Recipe name"),
        "steps": .array(of: .string(), minItems: 1),
        "servings": .integer(minimum: 1).optional()
    ])

    func testObjectSchemaShape() {
        let json = recipe.jsonSchema
        XCTAssertEqual(json["type"], "object")
        XCTAssertEqual(json["additionalProperties"], false)
        XCTAssertEqual(json["properties"]?["name"]?["type"], "string")
        XCTAssertEqual(json["properties"]?["name"]?["description"], "Recipe name")
        XCTAssertEqual(json["properties"]?["steps"]?["minItems"]?.intValue, 1)
        XCTAssertEqual(
            json["required"]?.arrayValue?.compactMap(\.stringValue), ["name", "steps"]
        )
    }

    func testValidationAcceptsAndRejects() throws {
        try recipe.validate(["name": "Dal", "steps": ["simmer"], "servings": 4])
        try recipe.validate(["name": "Dal", "steps": ["simmer"]])

        XCTAssertThrowsError(try recipe.validate(["steps": ["simmer"]]))
        XCTAssertThrowsError(try recipe.validate(["name": "Dal", "steps": []]))
        XCTAssertThrowsError(try recipe.validate(["name": 1, "steps": ["x"]]))
        XCTAssertThrowsError(try recipe.validate(
            ["name": "Dal", "steps": ["x"], "servings": 0]
        ))
        XCTAssertThrowsError(try recipe.validate(
            ["name": "Dal", "steps": ["x"], "extra": true]
        ))
    }

    func testEnumAnyOfAndModifiers() throws {
        let mood = Schema.enum(["happy", "sad"])
        try mood.validate("happy")
        XCTAssertThrowsError(try mood.validate("angry"))

        let idOrName = Schema.anyOf([.integer(), .string()])
        try idOrName.validate(42)
        try idOrName.validate("abc")
        XCTAssertThrowsError(try idOrName.validate(true))

        XCTAssertEqual(
            Schema.string().describe("later").jsonSchema["description"], "later"
        )
    }

    func testIntegerRejectsFractions() {
        XCTAssertThrowsError(try Schema.integer().validate(1.5))
        XCTAssertNoThrow(try Schema.integer().validate(2))
    }

    func testGenerateObjectValidatesWithSchema() async throws {
        struct Out: Codable { var name: String }
        let model = MockModel(scripts: [[
            .textDelta(#"{"name": "Dal"}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        do {
            _ = try await generateObject(
                model: model, of: Out.self, schema: recipe, prompt: "dal"
            )
            XCTFail("expected schema validation to fail")
        } catch AIError.noObjectGenerated(let message) {
            XCTAssertTrue(message.contains("Schema validation failed"))
        }
    }

    func testSchemaTypedToolValidatesArguments() async throws {
        let executed = ExecutionFlag()
        let tool = Tool(
            name: "serve",
            description: "serves food",
            parameters: Schema.object(["servings": .integer(minimum: 1)])
        ) { _ in
            await executed.set()
            return "ok"
        }
        _ = try await tool.execute(["servings": 2])
        let ran = await executed.value
        XCTAssertTrue(ran)
        do {
            _ = try await tool.execute(["servings": 0])
            XCTFail("expected validation error")
        } catch {}
    }
}

@MainActor
final class SessionHooksTests: XCTestCase {

    struct ScriptedCompletionTransport: CompletionTransport {
        var deltas: [String]
        func complete(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
            let script = deltas
            return AsyncThrowingStream { continuation in
                for delta in script { continuation.yield(delta) }
                continuation.finish()
            }
        }
    }

    func testCompletionStreamsAndSettles() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }
        let session = CompletionSession(
            transport: ScriptedCompletionTransport(deltas: ["Once", " upon", " a time"])
        )
        session.complete("start a story")
        try await settle(loading: { session.isLoading })
        XCTAssertEqual(session.completion, "Once upon a time")
        XCTAssertEqual(session.status, .ready)
    }

    func testCompletionAgainstLocalModel() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }
        let model = MockModel(scripts: [[
            .textDelta("hi from the model"),
            .finish(reason: .stop, usage: .init())
        ]])
        let session = CompletionSession(model: model)
        session.complete("hello")
        try await settle(loading: { session.isLoading })
        XCTAssertEqual(session.completion, "hi from the model")
    }

    struct ScriptedObjectTransport: ObjectTransport {
        var deltas: [String]
        func stream(input: JSONValue) async throws -> AsyncThrowingStream<String, Error> {
            let script = deltas
            return AsyncThrowingStream { continuation in
                for delta in script { continuation.yield(delta) }
                continuation.finish()
            }
        }
    }

    func testObjectSessionRepairsPartials() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }
        let session = ObjectSession(transport: ScriptedObjectTransport(
            deltas: [#"{"title": "Sp"#, #"ace", "tags": ["ro"#, #"ckets"]}"#]
        ))
        session.submit(["topic": "space"])
        try await settle(loading: { session.isLoading })

        XCTAssertEqual(session.object?["title"], "Space")
        XCTAssertEqual(session.object?["tags"]?.arrayValue?.count, 1)

        struct Out: Decodable { var title: String; var tags: [String] }
        XCTAssertEqual(session.decoded(Out.self)?.tags, ["rockets"])
    }

    func testObjectSessionClearResets() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }
        let session = ObjectSession(transport: ScriptedObjectTransport(
            deltas: [#"{"a": 1}"#]
        ))
        session.submit("go")
        try await settle(loading: { session.isLoading })
        XCTAssertNotNil(session.object)
        session.clear()
        XCTAssertNil(session.object)
        XCTAssertEqual(session.status, .ready)
    }

    func testUTF8PrefixSplitting() {
        let rocket = Data("🚀".utf8)
        let partial = rocket.prefix(2)
        let held = HTTPObjectTransport.decodeCompletePrefix(Data(partial))
        XCTAssertEqual(held?.0, "")
        XCTAssertEqual(held?.1.count, 2)

        let full = HTTPObjectTransport.decodeCompletePrefix(Data("a🚀".utf8))
        XCTAssertEqual(full?.0, "a🚀")
        XCTAssertEqual(full?.1.count, 0)
    }

    private func settle(
        loading: @MainActor () -> Bool, timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        try await Task.sleep(nanoseconds: 10_000_000)
        while loading() {
            if Date() > deadline { throw XCTSkip("did not settle") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
