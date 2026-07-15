import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIChatModel: LanguageModel {
    public let provider: String
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let queryParams: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.init(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            queryParams: queryParams,
            urlSession: urlSession,
            providerName: "openai"
        )
    }

    init(
        _ modelID: String,
        apiKey: String,
        baseURL: URL,
        headers: [String: String],
        queryParams: [String: String],
        urlSession: URLSession,
        providerName: String
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.queryParams = queryParams
        self.urlSession = urlSession
        self.provider = providerName
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
                var toolAccum: [Int: (id: String, name: String, args: String)] = [:]
                var finishReason: FinishReason = .stop
                var usage = Usage()
                var emittedSourceURLs = Set<String>()
                var logprobsContent: [JSONValue] = []

                do {
                    for try await sse in SSE.events(from: bytes) {
                        if sse.data == "[DONE]" { break }
                        guard let data = sse.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data)
                        else { continue }

                        if let u = chunk.usage ?? chunk.x_groq?.usage {
                            usage = Self.mapUsage(u)
                        }
                        for result in chunk.search_results ?? [] {
                            guard let url = result.url, emittedSourceURLs.insert(url).inserted
                            else { continue }
                            continuation.yield(.source(Source(
                                id: "source-\(emittedSourceURLs.count - 1)",
                                url: url,
                                title: result.title
                            )))
                        }
                        for citation in chunk.citations ?? []
                        where emittedSourceURLs.insert(citation).inserted {
                            continuation.yield(.source(
                                Source(id: "source-\(emittedSourceURLs.count - 1)", url: citation)
                            ))
                        }
                        var perplexity: [String: JSONValue] = [:]
                        if let images = chunk.images { perplexity["images"] = images }
                        if let related = chunk.related_questions {
                            perplexity["related_questions"] = related
                        }
                        if !perplexity.isEmpty {
                            continuation.yield(.providerMetadata(
                                .object(["perplexity": .object(perplexity)])
                            ))
                        }
                        guard let choice = chunk.choices?.first else { continue }

                        if let content = choice.delta?.content, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if let thinking = choice.delta?.reasoning_content ?? choice.delta?.reasoning,
                           !thinking.isEmpty {
                            continuation.yield(.reasoningDelta(thinking))
                        }
                        for tc in choice.delta?.tool_calls ?? [] {
                            let idx = tc.index ?? 0
                            var entry = toolAccum[idx] ?? (id: tc.id ?? "", name: "", args: "")
                            if let id = tc.id { entry.id = id }
                            if let name = tc.function?.name { entry.name = name }
                            if let a = tc.function?.arguments { entry.args += a }
                            toolAccum[idx] = entry
                        }
                        if let content = choice.logprobs?.content {
                            logprobsContent.append(contentsOf: content)
                        }
                        if let reason = choice.finish_reason {
                            finishReason = Self.mapFinishReason(reason)
                        }
                    }

                    for (_, t) in toolAccum.sorted(by: { $0.key < $1.key }) {
                        let args = (try? JSONDecoder().decode(
                            JSONValue.self, from: Data(t.args.utf8))) ?? .object([:])
                        continuation.yield(.toolCall(ToolCall(id: t.id, name: t.name, arguments: args)))
                    }
                    if !logprobsContent.isEmpty {
                        continuation.yield(.providerMetadata(
                            .object(["openai": .object(["logprobs": .array(logprobsContent)])])
                        ))
                    }
                    continuation.yield(.finish(reason: finishReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: requestURL(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            Self.requestBody(
                for: request, modelID: modelID,
                reasoningStyle: .forProvider(provider),
                providerName: provider
            )
        )
        return urlRequest
    }

    enum ReasoningWireStyle: Sendable {
        case openAI
        case compatible
        case fireworks
        case groq
        case xaiChat
        case deepseek
        case mistral
        case openRouter
        case alibaba
        case unsupported

        static func forProvider(_ name: String) -> ReasoningWireStyle {
            switch name {
            case "openai": return .openAI
            case "groq": return .groq
            case "deepseek": return .deepseek
            case "mistral": return .mistral
            case "perplexity": return .unsupported
            case "xai": return .xaiChat
            case "fireworks": return .fireworks
            case "openrouter": return .openRouter
            case "alibaba": return .alibaba
            default: return .compatible
            }
        }
    }

    private static func xaiModelSupportsReasoningEffort(_ modelID: String) -> Bool {
        modelID.range(
            of: #"^grok-4\.20(-\d{4})?-(non-)?reasoning$"#, options: .regularExpression
        ) == nil
    }

    private static let mistralReasoningModels: Set<String> = [
        "mistral-small-latest", "mistral-small-2603",
        "mistral-medium-3", "mistral-medium-3.5"
    ]

    static func mapUsage(_ u: OpenAIChunk.Usage) -> Usage {
        Usage(
            inputTokens: u.prompt_tokens ?? 0,
            outputTokens: u.completion_tokens ?? 0,
            cachedInputTokens: u.prompt_tokens_details?.cached_tokens ?? u.prompt_cache_hit_tokens,
            reasoningTokens: u.completion_tokens_details?.reasoning_tokens
        )
    }

    static func reasoningFields(
        _ reasoning: ReasoningEffort, style: ReasoningWireStyle, modelID: String
    ) -> [String: JSONValue] {
        guard reasoning.isCustom else { return [:] }
        func coerced(minimal: String, xhigh: String) -> String {
            switch reasoning {
            case .minimal: return minimal
            case .xhigh: return xhigh
            default: return reasoning.rawValue
            }
        }
        switch style {
        case .openAI:
            return ["reasoning_effort": .string(reasoning.rawValue)]
        case .compatible:
            guard reasoning != .none else { return [:] }
            return ["reasoning_effort": .string(reasoning.rawValue)]
        case .fireworks:
            guard reasoning != .none else { return [:] }
            return ["reasoning_effort": .string(coerced(minimal: "low", xhigh: "high"))]
        case .groq:
            return [
                "reasoning_format": .string("parsed"),
                "reasoning_effort": .string(reasoning == .none ? "none" : coerced(minimal: "low", xhigh: "high"))
            ]
        case .xaiChat:
            guard xaiModelSupportsReasoningEffort(modelID) else { return [:] }
            let effort = reasoning == .none ? "none" : coerced(minimal: "low", xhigh: "high")
            return ["reasoning_effort": .string(effort)]
        case .deepseek:
            var fields: [String: JSONValue] = [
                "thinking": .object([
                    "type": .string(reasoning == .none ? "disabled" : "enabled")
                ])
            ]
            if reasoning != .none {
                fields["reasoning_effort"] = .string(coerced(minimal: "low", xhigh: "max"))
            }
            return fields
        case .mistral:
            guard mistralReasoningModels.contains(modelID) else { return [:] }
            return ["reasoning_effort": .string(reasoning == .none ? "none" : "high")]
        case .openRouter:
            // OpenRouter reads reasoning effort from a nested object, not a top-level
            // reasoning_effort string: https://openrouter.ai/docs/use-cases/reasoning-tokens
            guard reasoning != .none else { return [:] }
            return ["reasoning": .object(["effort": .string(coerced(minimal: "low", xhigh: "high"))])]
        case .alibaba:
            if reasoning == .none { return ["enable_thinking": .bool(false)] }
            let budget: Double
            switch reasoning {
            case .minimal: budget = 1024
            case .low: budget = 4096
            case .medium: budget = 16384
            default: budget = 38912
            }
            return ["enable_thinking": .bool(true), "thinking_budget": .number(budget)]
        case .unsupported:
            return [:]
        }
    }

    static func requestBody(
        for request: LanguageModelRequest,
        modelID: String,
        reasoningStyle: ReasoningWireStyle = .compatible,
        providerName: String = ""
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "stream": .bool(true),
            "messages": .array(mapMessages(request.messages))
        ]
        body[reasoningStyle == .openAI ? "max_completion_tokens" : "max_tokens"]
            = .number(Double(request.maxOutputTokens))
        if let temp = request.temperature { body["temperature"] = .number(temp) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let presence = request.presencePenalty { body["presence_penalty"] = .number(presence) }
        if let frequency = request.frequencyPenalty { body["frequency_penalty"] = .number(frequency) }
        if let seed = request.seed {
            body[reasoningStyle == .mistral ? "random_seed" : "seed"] = .number(Double(seed))
        }
        if let topK = request.topK, reasoningStyle == .xaiChat {
            body["top_k"] = .number(Double(topK))
        }
        if !request.stopSequences.isEmpty {
            body["stop"] = .array(request.stopSequences.map { .string($0) })
        }
        if case .jsonNoSchema = request.responseFormat {
            body["response_format"] = .object(["type": "json_object"])
        }
        if case .json(let schema, let name, let description) = request.responseFormat {
            var jsonSchema: [String: JSONValue] = [
                "name": .string(name),
                "schema": schema,
                "strict": .bool(true)
            ]
            if let description { jsonSchema["description"] = .string(description) }
            body["response_format"] = .object([
                "type": "json_schema",
                "json_schema": .object(jsonSchema)
            ])
        }
        body["stream_options"] = .object(["include_usage": .bool(true)])
        let functionTools = request.functionTools
        let providerTools = request.providerToolEntries(for: providerName)
        if !functionTools.isEmpty || !providerTools.isEmpty {
            var toolsArray: [JSONValue] = functionTools.map {
                .object([
                    "type": "function",
                    "function": .object([
                        "name": .string($0.name),
                        "description": .string($0.description),
                        "parameters": $0.parameters
                    ])
                ])
            }
            toolsArray.append(contentsOf: providerTools)
            body["tools"] = .array(toolsArray)
            switch request.toolChoice {
            case .auto:
                break
            case .none:
                body["tool_choice"] = "none"
            case .required:
                body["tool_choice"] = "required"
            case .tool(let name):
                body["tool_choice"] = .object([
                    "type": "function",
                    "function": .object(["name": .string(name)])
                ])
            }
        }
        for (key, value) in reasoningFields(
            request.reasoning, style: reasoningStyle, modelID: modelID
        ) {
            body[key] = value
        }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }
        return .object(body)
    }

    func requestURL(path: String) -> URL {
        var url = baseURL.appendingPathComponent(path)
        if !queryParams.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryParams
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url ?? url
        }
        return url
    }

    private static func mapMessages(_ messages: [Message]) -> [JSONValue] {
        var out: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system:
                out.append(.object(["role": "system", "content": .string(message.text)]))
            case .user:
                out.append(.object(["role": "user", "content": userContent(message)]))
            case .assistant:
                var obj: [String: JSONValue] = ["role": "assistant"]
                let text = message.text
                obj["content"] = text.isEmpty ? .null : .string(text)
                let calls = message.content.compactMap { part -> JSONValue? in
                    guard case .toolCall(let c) = part else { return nil }
                    let argsString = (try? String(data: JSONEncoder().encode(c.arguments), encoding: .utf8)) ?? "{}"
                    return .object([
                        "id": .string(c.id),
                        "type": "function",
                        "function": .object([
                            "name": .string(c.name),
                            "arguments": .string(argsString)
                        ])
                    ])
                }
                if !calls.isEmpty { obj["tool_calls"] = .array(calls) }
                out.append(.object(obj))
            case .tool:
                for part in message.content {
                    guard case .toolResult(let r) = part else { continue }
                    let content: String = {
                        if case .string(let s) = r.output { return s }
                        return (try? String(data: JSONEncoder().encode(r.output), encoding: .utf8) ?? "") ?? ""
                    }()
                    out.append(.object([
                        "role": "tool",
                        "tool_call_id": .string(r.toolCallID),
                        "content": .string(content)
                    ]))
                }
            }
        }
        return out
    }

    private static func userContent(_ message: Message) -> JSONValue {
        let hasAttachments = message.content.contains {
            switch $0 {
            case .image, .file: return true
            default: return false
            }
        }
        guard hasAttachments else { return .string(message.text) }

        let parts = message.content.enumerated().compactMap { index, part -> JSONValue? in
            switch part {
            case .text(let text):
                return .object(["type": "text", "text": .string(text)])
            case .image(let image):
                return imageURLPart(
                    data: image.data, url: image.url, mediaType: image.resolvedMediaType
                )
            case .file(let file) where file.mediaType.hasPrefix("image/"):
                return imageURLPart(data: file.data, url: file.url, mediaType: file.mediaType)
            case .file(let file) where file.mediaType == "application/pdf":
                guard let data = file.data else { return nil }
                return .object(["type": "file", "file": .object([
                    "filename": .string(file.filename ?? "part-\(index).pdf"),
                    "file_data": .string(
                        "data:application/pdf;base64,\(data.base64EncodedString())"
                    )
                ])])
            default:
                return nil
            }
        }
        return .array(parts)
    }

    private static func imageURLPart(data: Data?, url: URL?, mediaType: String) -> JSONValue {
        let urlString = url?.absoluteString
            ?? "data:\(mediaType);base64,\(data?.base64EncodedString() ?? "")"
        return .object([
            "type": "image_url",
            "image_url": .object(["url": .string(urlString)])
        ])
    }

    private static func mapFinishReason(_ reason: String) -> FinishReason {
        switch reason {
        case "stop": .stop
        case "length": .length
        case "tool_calls": .toolCalls
        case "content_filter": .contentFilter
        default: .other
        }
    }
}

struct OpenAIChunk: Decodable {
    var choices: [Choice]?
    var usage: Usage?
    var x_groq: XGroq?
    var citations: [String]?
    var search_results: [SearchResult]?
    var images: JSONValue?
    var related_questions: JSONValue?

    struct XGroq: Decodable {
        var usage: Usage?
    }
    struct SearchResult: Decodable {
        var title: String?
        var url: String?
        var date: String?
    }
    struct Choice: Decodable {
        var delta: Delta?
        var finish_reason: String?
        var logprobs: Logprobs?
    }
    struct Logprobs: Decodable {
        var content: [JSONValue]?
    }
    struct Delta: Decodable {
        var content: String?
        var reasoning_content: String?
        var reasoning: String?
        var tool_calls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content, reasoning_content, reasoning, tool_calls
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reasoning_content = try? container.decodeIfPresent(String.self, forKey: .reasoning_content)
            reasoning = try? container.decodeIfPresent(String.self, forKey: .reasoning)
            tool_calls = try? container.decodeIfPresent([ToolCallDelta].self, forKey: .tool_calls)
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                content = text
            } else if let parts = try? container.decodeIfPresent([ContentPart].self, forKey: .content) {
                var text = ""
                var thinking = ""
                for part in parts {
                    switch part.type {
                    case "text":
                        text += part.text ?? ""
                    case "thinking":
                        for chunk in part.thinking ?? [] where chunk.type == "text" {
                            thinking += chunk.text ?? ""
                        }
                    default:
                        break
                    }
                }
                content = text.isEmpty ? nil : text
                if !thinking.isEmpty {
                    reasoning_content = (reasoning_content ?? "") + thinking
                }
            }
        }
    }
    struct ContentPart: Decodable {
        var type: String?
        var text: String?
        var thinking: [ContentPart]?
    }
    struct ToolCallDelta: Decodable {
        var index: Int?
        var id: String?
        var function: Function?
    }
    struct Function: Decodable {
        var name: String?
        var arguments: String?
    }
    struct Usage: Decodable {
        var prompt_tokens: Int?
        var completion_tokens: Int?
        var prompt_tokens_details: PromptTokensDetails?
        var completion_tokens_details: CompletionTokensDetails?
        var prompt_cache_hit_tokens: Int?

        struct PromptTokensDetails: Decodable {
            var cached_tokens: Int?
        }
        struct CompletionTokensDetails: Decodable {
            var reasoning_tokens: Int?
        }
    }
}
