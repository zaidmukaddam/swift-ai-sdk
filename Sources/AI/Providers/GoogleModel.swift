import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GoogleModel: LanguageModel {
    public let provider = "google"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
            ?? ProcessInfo.processInfo.environment["GOOGLE_GENERATIVE_AI_API_KEY"]
            ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        try await Self.streamGenerateContent(buildURLRequest(request), urlSession: urlSession)
    }

    static func streamGenerateContent(
        _ urlRequest: URLRequest,
        urlSession: URLSession
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let (bytes, response) = try await urlSession.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw AIError.http(status: http.statusCode, body: body)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var toolCallIndex = 0
                var hadToolCalls = false
                var finishReason: String?
                var usage: GoogleChunk.UsageMetadata?

                do {
                    for try await sse in SSE.events(from: bytes) {
                        guard let data = sse.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GoogleChunk.self, from: data)
                        else { continue }

                        if let meta = chunk.usageMetadata { usage = meta }
                        for candidate in chunk.candidates ?? [] {
                            if let reason = candidate.finishReason { finishReason = reason }
                            for part in candidate.content?.parts ?? [] {
                                if part.thought == true, let text = part.text {
                                    continuation.yield(.reasoningDelta(text))
                                } else if let text = part.text {
                                    continuation.yield(.textDelta(text))
                                }
                                if let call = part.functionCall, let name = call.name {
                                    hadToolCalls = true
                                    let id = "call_\(toolCallIndex)"
                                    toolCallIndex += 1
                                    continuation.yield(.toolCallStart(id: id, name: name))
                                    continuation.yield(.toolCall(ToolCall(
                                        id: id, name: name, arguments: call.args ?? .object([:])
                                    )))
                                }
                            }
                        }
                    }
                    continuation.yield(.finish(
                        reason: Self.mapFinishReason(finishReason, hadToolCalls: hadToolCalls),
                        usage: Usage(
                            inputTokens: usage?.promptTokenCount ?? 0,
                            outputTokens: (usage?.candidatesTokenCount ?? 0)
                                + (usage?.thoughtsTokenCount ?? 0),
                            cachedInputTokens: usage?.cachedContentTokenCount,
                            reasoningTokens: usage?.thoughtsTokenCount
                        )
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        guard let url = URL(
            string: "\(baseURL.absoluteString)/models/\(modelID):streamGenerateContent?alt=sse"
        ) else {
            throw AIError.invalidRequest("could not build Google URL for model \(modelID)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(Self.requestBody(for: request, modelID: modelID))
        return urlRequest
    }

    static func requestBody(for request: LanguageModelRequest, modelID: String = "") -> JSONValue {
        var body: [String: JSONValue] = [
            "contents": .array(mapContents(request.messages))
        ]
        if let system = systemInstruction(request.messages) {
            body["systemInstruction"] = system
        }
        let functionTools = request.functionTools
        let providerTools = request.providerToolEntries(for: "google")
        if !functionTools.isEmpty || !providerTools.isEmpty {
            var toolsArray: [JSONValue] = []
            if !functionTools.isEmpty {
                toolsArray.append(.object([
                    "functionDeclarations": .array(functionTools.map {
                        .object([
                            "name": .string($0.name),
                            "description": .string($0.description),
                            "parameters": cleanSchema($0.parameters)
                        ])
                    })
                ]))
            }
            toolsArray.append(contentsOf: providerTools)
            body["tools"] = .array(toolsArray)
            switch request.toolChoice {
            case .auto:
                break
            case .none:
                body["toolConfig"] = .object([
                    "functionCallingConfig": .object(["mode": "NONE"])
                ])
            case .required:
                body["toolConfig"] = .object([
                    "functionCallingConfig": .object(["mode": "ANY"])
                ])
            case .tool(let name):
                body["toolConfig"] = .object([
                    "functionCallingConfig": .object([
                        "mode": "ANY",
                        "allowedFunctionNames": .array([.string(name)])
                    ])
                ])
            }
        }

        var generationConfig: [String: JSONValue] = [
            "maxOutputTokens": .number(Double(request.maxOutputTokens))
        ]
        if let temp = request.temperature { generationConfig["temperature"] = .number(temp) }
        if let topP = request.topP { generationConfig["topP"] = .number(topP) }
        if let topK = request.topK { generationConfig["topK"] = .number(Double(topK)) }
        if let presence = request.presencePenalty {
            generationConfig["presencePenalty"] = .number(presence)
        }
        if let frequency = request.frequencyPenalty {
            generationConfig["frequencyPenalty"] = .number(frequency)
        }
        if let seed = request.seed { generationConfig["seed"] = .number(Double(seed)) }
        if !request.stopSequences.isEmpty {
            generationConfig["stopSequences"] = .array(request.stopSequences.map { .string($0) })
        }
        if case .jsonNoSchema = request.responseFormat {
            generationConfig["responseMimeType"] = .string("application/json")
        }
        if case .json(let schema, _, _) = request.responseFormat {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = cleanSchema(schema)
        }
        if let thinkingConfig = reasoningThinkingConfig(request.reasoning, modelID: modelID) {
            generationConfig["thinkingConfig"] = thinkingConfig
        }
        body["generationConfig"] = .object(generationConfig)

        if case .object(let opts)? = request.providerOptions {
            for (k, v) in opts { body[k] = v }
        }
        return .object(body)
    }

    static func reasoningThinkingConfig(
        _ reasoning: ReasoningEffort, modelID: String
    ) -> JSONValue? {
        guard reasoning.isCustom else { return nil }
        let id = modelID.lowercased()
        let isGemini3 = id.range(
            of: "gemini-3[.-]", options: .regularExpression
        ) != nil || id.hasSuffix("gemini-3")
        if isGemini3 && !id.contains("gemini-3-pro-image") {
            let level: String
            switch reasoning {
            case .none, .minimal: level = "minimal"
            case .xhigh: level = "high"
            default: level = reasoning.rawValue
            }
            return .object(["thinkingLevel": .string(level)])
        }
        if reasoning == .none {
            return .object(["thinkingBudget": .number(0)])
        }
        let maxBudget = id.contains("2.5-pro") || id.contains("gemini-3-pro-image")
            ? 32768 : 24576
        guard let budget = reasoning.budget(
            maxOutputTokens: 65536, maxBudget: maxBudget, minBudget: 0
        ) else { return nil }
        return .object(["thinkingBudget": .number(Double(budget))])
    }

    private static func systemInstruction(_ messages: [Message]) -> JSONValue? {
        let system = messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        guard !system.isEmpty else { return nil }
        return .object(["parts": .array([.object(["text": .string(system)])])])
    }

    private static func mapContents(_ messages: [Message]) -> [JSONValue] {
        messages.compactMap { message -> JSONValue? in
            let role: String
            let parts: [JSONValue]
            switch message.role {
            case .system:
                return nil
            case .user:
                role = "user"
                parts = message.content.compactMap { part -> JSONValue? in
                    switch part {
                    case .text(let t):
                        return t.isEmpty ? nil : .object(["text": .string(t)])
                    case .image(let image):
                        return mediaPart(
                            data: image.data, url: image.url,
                            mediaType: image.resolvedMediaType
                        )
                    case .file(let file):
                        return mediaPart(
                            data: file.data, url: file.url, mediaType: file.mediaType
                        )
                    case .toolCall, .toolResult, .toolApprovalResponse:
                        return nil
                    }
                }
            case .assistant:
                role = "model"
                parts = message.content.compactMap { part -> JSONValue? in
                    switch part {
                    case .text(let t):
                        return .object(["text": .string(t)])
                    case .toolCall(let call):
                        return .object(["functionCall": .object([
                            "name": .string(call.name),
                            "args": call.arguments
                        ])])
                    case .toolResult, .image, .file, .toolApprovalResponse:
                        return nil
                    }
                }
            case .tool:
                role = "user"
                parts = message.content.compactMap { part -> JSONValue? in
                    guard case .toolResult(let result) = part else { return nil }
                    let response: JSONValue
                    if case .object = result.output {
                        response = result.output
                    } else {
                        response = .object(["result": result.output])
                    }
                    return .object(["functionResponse": .object([
                        "name": .string(result.name),
                        "response": response
                    ])])
                }
            }
            guard !parts.isEmpty else { return nil }
            return .object(["role": .string(role), "parts": .array(parts)])
        }
    }

    private static func mediaPart(data: Data?, url: URL?, mediaType: String) -> JSONValue? {
        if let data {
            return .object(["inlineData": .object([
                "mimeType": .string(mediaType),
                "data": .string(data.base64EncodedString())
            ])])
        }
        if let url {
            return .object(["fileData": .object([
                "mimeType": .string(mediaType),
                "fileUri": .string(url.absoluteString)
            ])])
        }
        return nil
    }

    static func cleanSchema(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(let object):
            var cleaned: [String: JSONValue] = [:]
            for (key, value) in object where key != "$schema" && key != "additionalProperties" {
                cleaned[key] = cleanSchema(value)
            }
            return .object(cleaned)
        case .array(let items):
            return .array(items.map(cleanSchema))
        default:
            return schema
        }
    }

    static func mapFinishReason(_ raw: String?, hadToolCalls: Bool) -> FinishReason {
        switch raw ?? "STOP" {
        case "STOP":
            hadToolCalls ? .toolCalls : .stop
        case "MAX_TOKENS":
            .length
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY":
            .contentFilter
        case "MALFORMED_FUNCTION_CALL":
            .error
        default:
            .other
        }
    }
}

public extension GoogleModel {
    enum Tools {
        public static func googleSearch(name: String = "google_search") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "google", id: "google.google_search", name: name,
                args: .object(["googleSearch": .object([:])])
            )
        }

        public static func urlContext(name: String = "url_context") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "google", id: "google.url_context", name: name,
                args: .object(["urlContext": .object([:])])
            )
        }

        public static func codeExecution(name: String = "code_execution") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "google", id: "google.code_execution", name: name,
                args: .object(["codeExecution": .object([:])])
            )
        }

        public static func enterpriseWebSearch(name: String = "enterprise_web_search") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "google", id: "google.enterprise_web_search", name: name,
                args: .object(["enterpriseWebSearch": .object([:])])
            )
        }

        public static func googleMaps(name: String = "google_maps") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "google", id: "google.google_maps", name: name,
                args: .object(["googleMaps": .object([:])])
            )
        }

        public static func fileSearch(
            fileSearchStoreNames: [String]? = nil,
            name: String = "file_search"
        ) -> ProviderDefinedTool {
            var config: [String: JSONValue] = [:]
            if let fileSearchStoreNames {
                config["fileSearchStoreNames"] = .array(fileSearchStoreNames.map { .string($0) })
            }
            return ProviderDefinedTool(
                provider: "google", id: "google.file_search", name: name,
                args: .object(["fileSearch": .object(config)])
            )
        }
    }
}

private struct GoogleChunk: Decodable {
    var candidates: [Candidate]?
    var usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        var content: Content?
        var finishReason: String?
    }
    struct Content: Decodable {
        var parts: [Part]?
    }
    struct Part: Decodable {
        var text: String?
        var thought: Bool?
        var functionCall: FunctionCall?

        enum CodingKeys: String, CodingKey {
            case text, thought, functionCall
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try? container.decodeIfPresent(String.self, forKey: .text)
            thought = try? container.decodeIfPresent(Bool.self, forKey: .thought)
            functionCall = try? container.decodeIfPresent(FunctionCall.self, forKey: .functionCall)
        }
    }
    struct FunctionCall: Decodable {
        var name: String?
        var args: JSONValue?
    }
    struct UsageMetadata: Decodable {
        var promptTokenCount: Int?
        var candidatesTokenCount: Int?
        var thoughtsTokenCount: Int?
        var cachedContentTokenCount: Int?
    }
}
