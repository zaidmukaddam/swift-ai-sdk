import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CohereModel: LanguageModel {
    public let provider = "cohere"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.cohere.com/v2")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["COHERE_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let urlRequest = try buildURLRequest(request)
        let (bytes, response) = try await urlSession.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw AIError.http(status: http.statusCode, body: body)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = StreamDecoder()
                do {
                    for try await sse in SSE.events(from: bytes) {
                        for part in decoder.parts(forEventData: sse.data) {
                            continuation.yield(part)
                        }
                    }
                    continuation.yield(decoder.finishPart())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            Self.requestBody(for: request, modelID: modelID)
        )
        return urlRequest
    }

    static func requestBody(for request: LanguageModelRequest, modelID: String) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "stream": .bool(true),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            "messages": .array(mapMessages(request.messages))
        ]
        if let temp = request.temperature { body["temperature"] = .number(temp) }
        if let topP = request.topP { body["p"] = .number(topP) }
        if let topK = request.topK { body["k"] = .number(Double(topK)) }
        if let presence = request.presencePenalty { body["presence_penalty"] = .number(presence) }
        if let frequency = request.frequencyPenalty { body["frequency_penalty"] = .number(frequency) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if !request.stopSequences.isEmpty {
            body["stop_sequences"] = .array(request.stopSequences.map { .string($0) })
        }
        if let thinking = thinkingField(
            request.reasoning, maxOutputTokens: request.maxOutputTokens, modelID: modelID
        ) {
            body["thinking"] = thinking
        }
        if case .jsonNoSchema = request.responseFormat {
            body["response_format"] = .object(["type": "json_object"])
        }
        if case .json(let schema, _, _) = request.responseFormat {
            body["response_format"] = .object([
                "type": "json_object",
                "json_schema": schema
            ])
        }
        if !request.tools.isEmpty {
            var visibleTools = request.tools
            switch request.toolChoice {
            case .auto:
                break
            case .none:
                body["tool_choice"] = "NONE"
            case .required:
                body["tool_choice"] = "REQUIRED"
            case .tool(let name):
                visibleTools = visibleTools.filter { $0.name == name }
                body["tool_choice"] = "REQUIRED"
            }
            body["tools"] = .array(visibleTools.map {
                .object([
                    "type": "function",
                    "function": .object([
                        "name": .string($0.name),
                        "description": .string($0.description),
                        "parameters": $0.parameters
                    ])
                ])
            })
        }
        if case .object(let opts)? = request.providerOptions {
            for (k, v) in opts { body[k] = v }
        }
        return .object(body)
    }

    static func thinkingField(
        _ reasoning: ReasoningEffort, maxOutputTokens: Int, modelID: String
    ) -> JSONValue? {
        guard modelID.contains("reasoning") else { return nil }
        switch reasoning {
        case .providerDefault:
            return nil
        case .none:
            return .object(["type": "disabled"])
        default:
            var thinking: [String: JSONValue] = ["type": "enabled"]
            if let budget = reasoning.budget(
                maxOutputTokens: maxOutputTokens, maxBudget: 31000, minBudget: 1024
            ) {
                thinking["token_budget"] = .number(Double(budget))
            }
            return .object(thinking)
        }
    }

    static func mapMessages(_ messages: [Message]) -> [JSONValue] {
        var mapped: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system:
                let text = message.text
                guard !text.isEmpty else { break }
                mapped.append(.object(["role": "system", "content": .string(text)]))

            case .user:
                let images = message.content.compactMap { part -> JSONValue? in
                    guard case .image(let image) = part, let data = image.data else { return nil }
                    let dataURL = "data:\(image.resolvedMediaType);base64,\(data.base64EncodedString())"
                    return .object([
                        "type": "image_url",
                        "image_url": .object(["url": .string(dataURL)])
                    ])
                }
                let text = message.text
                if images.isEmpty {
                    guard !text.isEmpty else { break }
                    mapped.append(.object(["role": "user", "content": .string(text)]))
                } else {
                    var contentParts: [JSONValue] = []
                    if !text.isEmpty {
                        contentParts.append(.object(["type": "text", "text": .string(text)]))
                    }
                    contentParts.append(contentsOf: images)
                    mapped.append(.object(["role": "user", "content": .array(contentParts)]))
                }

            case .assistant:
                let toolCalls = message.content.compactMap { part -> JSONValue? in
                    guard case .toolCall(let call) = part else { return nil }
                    return .object([
                        "id": .string(call.id),
                        "type": "function",
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(jsonString(call.arguments))
                        ])
                    ])
                }
                if toolCalls.isEmpty {
                    let text = message.text
                    guard !text.isEmpty else { break }
                    mapped.append(.object(["role": "assistant", "content": .string(text)]))
                } else {
                    mapped.append(.object([
                        "role": "assistant",
                        "tool_calls": .array(toolCalls)
                    ]))
                }

            case .tool:
                for part in message.content {
                    guard case .toolResult(let result) = part else { continue }
                    mapped.append(.object([
                        "role": "tool",
                        "tool_call_id": .string(result.toolCallID),
                        "content": .string(stringify(result.output))
                    ]))
                }
            }
        }
        return mapped
    }

    static func mapFinishReason(_ raw: String) -> FinishReason {
        switch raw {
        case "COMPLETE", "STOP_SEQUENCE": .stop
        case "MAX_TOKENS": .length
        case "ERROR": .error
        case "TOOL_CALL": .toolCalls
        default: .other
        }
    }

    struct StreamDecoder {
        private var pendingToolCall: (id: String, name: String, arguments: String)?
        private var hadToolCalls = false
        private var sourceCount = 0
        private var finishReason: FinishReason?
        private var usage = Usage()

        mutating func parts(forEventData data: String) -> [StreamPart] {
            guard let payload = try? JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)),
                  let type = payload["type"]?.stringValue
            else { return [] }

            switch type {
            case "content-start", "content-delta":
                let content = payload["delta"]?["message"]?["content"]
                if let thinking = content?["thinking"]?.stringValue {
                    return thinking.isEmpty ? [] : [.reasoningDelta(thinking)]
                }
                if let text = content?["text"]?.stringValue, !text.isEmpty {
                    return [.textDelta(text)]
                }
                return []

            case "tool-call-start":
                guard let call = payload["delta"]?["message"]?["tool_calls"],
                      let id = call["id"]?.stringValue,
                      let name = call["function"]?["name"]?.stringValue
                else { return [] }
                let initial = call["function"]?["arguments"]?.stringValue ?? ""
                pendingToolCall = (id: id, name: name, arguments: initial)
                var parts: [StreamPart] = [.toolCallStart(id: id, name: name)]
                if !initial.isEmpty {
                    parts.append(.toolArgumentsDelta(id: id, partialJSON: initial))
                }
                return parts

            case "tool-call-delta":
                guard var call = pendingToolCall,
                      let delta = payload["delta"]?["message"]?["tool_calls"]?["function"]?["arguments"]?.stringValue,
                      !delta.isEmpty
                else { return [] }
                call.arguments += delta
                pendingToolCall = call
                return [.toolArgumentsDelta(id: call.id, partialJSON: delta)]

            case "tool-call-end":
                guard let call = pendingToolCall else { return [] }
                pendingToolCall = nil
                hadToolCalls = true
                return [.toolCall(ToolCall(
                    id: call.id,
                    name: call.name,
                    arguments: Self.parseToolArguments(call.arguments)
                ))]

            case "citation-start":
                guard let citation = payload["delta"]?["message"]?["citations"] else { return [] }
                let document = citation["sources"]?.arrayValue?.first?["document"]
                let source = Source(
                    id: "source-\(sourceCount)",
                    url: document?["url"]?.stringValue ?? "",
                    title: document?["title"]?.stringValue ?? "Document"
                )
                sourceCount += 1
                return [.source(source)]

            case "message-end":
                if let reason = payload["delta"]?["finish_reason"]?.stringValue {
                    finishReason = CohereModel.mapFinishReason(reason)
                }
                if let tokens = payload["delta"]?["usage"]?["tokens"] {
                    usage = Usage(
                        inputTokens: tokens["input_tokens"]?.intValue ?? 0,
                        outputTokens: tokens["output_tokens"]?.intValue ?? 0
                    )
                }
                return []

            default:
                return []
            }
        }

        func finishPart() -> StreamPart {
            .finish(
                reason: finishReason ?? (hadToolCalls ? .toolCalls : .stop),
                usage: usage
            )
        }

        static func parseToolArguments(_ raw: String) -> JSONValue {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "null",
                  let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
            else { return .object([:]) }
            return value
        }
    }

    private static func jsonString(_ value: JSONValue) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func stringify(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        return jsonString(value)
    }
}

public struct CohereEmbeddingModel: EmbeddingModel {
    public enum InputType: String, Sendable {
        case searchDocument = "search_document"
        case searchQuery = "search_query"
        case classification = "classification"
        case clustering = "clustering"
    }

    public enum Truncate: String, Sendable {
        case none = "NONE"
        case start = "START"
        case end = "END"
    }

    public let provider = "cohere"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let inputType: InputType
    private let truncate: Truncate?
    private let outputDimension: Int?

    static let maxTextsPerCall = 96

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.cohere.com/v2")!,
        inputType: InputType = .searchQuery,
        truncate: Truncate? = nil,
        outputDimension: Int? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["COHERE_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.inputType = inputType
        self.truncate = truncate
        self.outputDimension = outputDimension
        self.headers = headers
        self.urlSession = urlSession
    }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        var embeddings: [[Double]] = []
        var usage = Usage()
        for start in stride(from: 0, to: texts.count, by: Self.maxTextsPerCall) {
            let batch = Array(texts[start..<min(start + Self.maxTextsPerCall, texts.count)])
            let response = try await embedBatch(batch)
            embeddings += response.embeddings
            usage = usage + response.usage
        }
        return EmbeddingResponse(embeddings: embeddings, usage: usage)
    }

    private func embedBatch(_ texts: [String]) async throws -> EmbeddingResponse {
        let urlRequest = try buildURLRequest(texts)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.parseResponse(data)
    }

    func buildURLRequest(_ texts: [String]) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("embed"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(Self.requestBody(
            texts: texts,
            modelID: modelID,
            inputType: inputType,
            truncate: truncate,
            outputDimension: outputDimension
        ))
        return urlRequest
    }

    static func requestBody(
        texts: [String],
        modelID: String,
        inputType: InputType,
        truncate: Truncate?,
        outputDimension: Int?
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "texts": .array(texts.map { .string($0) }),
            "embedding_types": .array(["float"]),
            "input_type": .string(inputType.rawValue)
        ]
        if let truncate { body["truncate"] = .string(truncate.rawValue) }
        if let outputDimension { body["output_dimension"] = .number(Double(outputDimension)) }
        return .object(body)
    }

    static func parseResponse(_ data: Data) throws -> EmbeddingResponse {
        let decoded = try JSONDecoder().decode(CohereEmbedResponseBody.self, from: data)
        guard let vectors = decoded.embeddings?.float else {
            throw AIError.decoding("Cohere embed response contained no float embeddings")
        }
        return EmbeddingResponse(
            embeddings: vectors,
            usage: Usage(
                inputTokens: Int(decoded.meta?.billed_units?.input_tokens ?? 0),
                outputTokens: 0
            )
        )
    }
}

private struct CohereEmbedResponseBody: Decodable {
    var embeddings: Embeddings?
    var meta: Meta?

    struct Embeddings: Decodable { var float: [[Double]]? }
    struct Meta: Decodable { var billed_units: BilledUnits? }
    struct BilledUnits: Decodable { var input_tokens: Double? }
}
