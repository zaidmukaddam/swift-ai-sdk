import Foundation

public struct GenerateObjectResult<T: Sendable>: Sendable {
    public var object: T
    public var rawJSON: JSONValue
    public var finishReason: FinishReason
    public var usage: Usage
}

public func generateObject<T: Decodable & Sendable>(
    model: any LanguageModel,
    of type: T.Type = T.self,
    schema: JSONValue,
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2,
    repairText: (@Sendable (String, any Error) async -> String?)? = nil
) async throws -> GenerateObjectResult<T> {
    let outcome = try await drainObjectStream(
        model: model,
        responseFormat: .json(schema: schema, name: schemaName, description: schemaDescription),
        messages: assembleMessages(messages: messages, system: system, prompt: prompt),
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries,
        onTextDelta: nil, repairText: repairText
    )

    guard let json = outcome.json else {
        throw AIError.noObjectGenerated(outcome.rawText)
    }
    do {
        let object = try json.decode(T.self)
        return GenerateObjectResult(
            object: object, rawJSON: json,
            finishReason: outcome.finishReason, usage: outcome.usage
        )
    } catch {
        throw AIError.noObjectGenerated("Decoding failed: \(error). JSON: \(outcome.rawText)")
    }
}

public func generateObjectArray<T: Decodable & Sendable>(
    model: any LanguageModel,
    of type: T.Type = T.self,
    elementSchema: JSONValue,
    schemaName: String = "elements",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2,
    repairText: (@Sendable (String, any Error) async -> String?)? = nil
) async throws -> GenerateObjectResult<[T]> {
    let wrapperSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "elements": .object(["type": .string("array"), "items": elementSchema])
        ]),
        "required": .array([.string("elements")]),
        "additionalProperties": .bool(false)
    ])
    let outcome = try await drainObjectStream(
        model: model,
        responseFormat: .json(schema: wrapperSchema, name: schemaName, description: schemaDescription),
        messages: assembleMessages(messages: messages, system: system, prompt: prompt),
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries,
        onTextDelta: nil, repairText: repairText
    )

    guard let json = outcome.json, let elements = json["elements"] else {
        throw AIError.noObjectGenerated(outcome.rawText)
    }
    do {
        let objects = try elements.decode([T].self)
        return GenerateObjectResult(
            object: objects, rawJSON: json,
            finishReason: outcome.finishReason, usage: outcome.usage
        )
    } catch {
        throw AIError.noObjectGenerated("Decoding failed: \(error). JSON: \(outcome.rawText)")
    }
}

public struct StreamObjectResult: Sendable {
    public let partialObjectStream: AsyncThrowingStream<JSONValue, Error>

    public func elementStream() -> AsyncThrowingStream<JSONValue, Error> {
        let partials = partialObjectStream
        return AsyncThrowingStream { continuation in
            let task = Task {
                var published = 0
                var latest: [JSONValue] = []
                do {
                    for try await partial in partials {
                        guard let elements = partial.arrayValue else { continue }
                        latest = elements
                        while published < elements.count - 1 {
                            continuation.yield(elements[published])
                            published += 1
                        }
                    }
                    while published < latest.count {
                        continuation.yield(latest[published])
                        published += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public func streamObject(
    model: any LanguageModel,
    schema: JSONValue,
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) -> StreamObjectResult {
    let assembled = assembleMessages(messages: messages, system: system, prompt: prompt)
    let stream = AsyncThrowingStream<JSONValue, Error> { continuation in
        let task = Task {
            do {
                let previous = Box<JSONValue?>(nil)
                let outcome = try await drainObjectStream(
                    model: model,
                    responseFormat: .json(
                        schema: schema, name: schemaName, description: schemaDescription
                    ),
                    messages: assembled,
                    maxOutputTokens: maxOutputTokens, temperature: temperature,
                    providerOptions: providerOptions, maxRetries: maxRetries,
                    onTextDelta: { accumulated in
                        if let partial = PartialJSON.parse(accumulated), partial != previous.value {
                            previous.value = partial
                            continuation.yield(partial)
                        }
                    }
                )
                if let json = outcome.json, json != previous.value {
                    continuation.yield(json)
                }
                if outcome.json == nil {
                    throw AIError.noObjectGenerated(outcome.rawText)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
    return StreamObjectResult(partialObjectStream: stream)
}

public func generateJSON(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateObjectResult<JSONValue> {
    let jsonInstruction = "Respond only with valid JSON. Do not include any other text."
    let combinedSystem = [system, jsonInstruction].compactMap { $0 }.joined(separator: "\n\n")
    let outcome = try await drainObjectStream(
        model: model,
        responseFormat: .jsonNoSchema,
        messages: assembleMessages(messages: messages, system: combinedSystem, prompt: prompt),
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries,
        onTextDelta: nil
    )
    guard let json = outcome.json else {
        throw AIError.noObjectGenerated(outcome.rawText)
    }
    return GenerateObjectResult(
        object: json, rawJSON: json,
        finishReason: outcome.finishReason, usage: outcome.usage
    )
}

public struct GenerateEnumResult: Sendable {
    public var value: String
    public var finishReason: FinishReason
    public var usage: Usage
}

public func generateEnum(
    model: any LanguageModel,
    values: [String],
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateEnumResult {
    guard !values.isEmpty else {
        throw AIError.invalidRequest("generateEnum requires at least one value")
    }
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "result": ["type": "string", "enum": .array(values.map { .string($0) })]
        ],
        "required": ["result"],
        "additionalProperties": false
    ]
    let outcome = try await drainObjectStream(
        model: model,
        responseFormat: .json(schema: schema, name: "enum"),
        messages: assembleMessages(messages: messages, system: system, prompt: prompt),
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries,
        onTextDelta: nil
    )
    guard let result = outcome.json?["result"]?.stringValue, values.contains(result) else {
        throw AIError.noObjectGenerated(
            "Expected one of \(values), got: \(outcome.rawText)"
        )
    }
    return GenerateEnumResult(
        value: result, finishReason: outcome.finishReason, usage: outcome.usage
    )
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private struct ObjectOutcome {
    var json: JSONValue?
    var rawText: String
    var finishReason: FinishReason
    var usage: Usage
}

private func drainObjectStream(
    model: any LanguageModel,
    responseFormat: ResponseFormat,
    messages: [Message],
    maxOutputTokens: Int,
    temperature: Double?,
    providerOptions: JSONValue?,
    maxRetries: Int,
    onTextDelta: (@Sendable (String) -> Void)?,
    repairText: (@Sendable (String, any Error) async -> String?)? = nil
) async throws -> ObjectOutcome {
    let request = LanguageModelRequest(
        messages: messages,
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        responseFormat: responseFormat,
        providerOptions: providerOptions
    )
    let stream = try await Retry.withRetries(maxRetries) {
        try await model.stream(request)
    }

    var text = ""
    var argumentsText = ""
    var structuredCall: ToolCall?
    var finishReason: FinishReason = .stop
    var usage = Usage()

    for try await part in stream {
        switch part {
        case .textDelta(let t):
            text += t
            onTextDelta?(text)
        case .toolArgumentsDelta(_, let fragment):
            argumentsText += fragment
            onTextDelta?(argumentsText)
        case .toolCall(let call):
            if !call.providerExecuted { structuredCall = call }
        case .finish(let reason, let u):
            finishReason = reason
            usage = u
        case .reasoningDelta, .toolCallStart, .toolResult, .source, .providerMetadata:
            break
        }
    }

    let rawText = text.isEmpty ? argumentsText : text
    var json: JSONValue? = {
        if let call = structuredCall { return call.arguments }
        guard let data = rawText.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return PartialJSON.parse(rawText) }
        return value
    }()

    if json == nil, let repairText,
       let repaired = await repairText(rawText, AIError.noObjectGenerated(rawText)),
       let data = repaired.data(using: .utf8),
       let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
        json = value
    }

    return ObjectOutcome(json: json, rawText: rawText, finishReason: finishReason, usage: usage)
}
