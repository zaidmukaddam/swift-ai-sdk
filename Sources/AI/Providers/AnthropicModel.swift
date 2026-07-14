import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AnthropicModel: LanguageModel {
    public let provider = "anthropic"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let anthropicVersion: String
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        anthropicVersion: String = "2023-06-01",
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.anthropicVersion = anthropicVersion
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
                var toolBlocks: [Int: (id: String, name: String, json: String)] = [:]
                var inputTokens = 0
                var outputTokens = 0
                var cachedTokens: Int?
                var finishReason: FinishReason = .stop

                do {
                    for try await sse in SSE.events(from: bytes) {
                        guard let data = sse.data.data(using: .utf8),
                              let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data)
                        else { continue }

                        switch event.type {
                        case "message_start":
                            inputTokens = event.message?.usage?.input_tokens ?? 0
                            cachedTokens = event.message?.usage?.cache_read_input_tokens

                        case "content_block_start":
                            if let block = event.content_block, block.type == "tool_use",
                               let idx = event.index, let id = block.id, let name = block.name {
                                toolBlocks[idx] = (id: id, name: name, json: "")
                                continuation.yield(.toolCallStart(id: id, name: name))
                            }

                        case "content_block_delta":
                            guard let delta = event.delta, let idx = event.index else { break }
                            switch delta.type {
                            case "text_delta":
                                if let t = delta.text { continuation.yield(.textDelta(t)) }
                            case "thinking_delta":
                                if let t = delta.thinking { continuation.yield(.reasoningDelta(t)) }
                            case "input_json_delta":
                                if let frag = delta.partial_json {
                                    toolBlocks[idx]?.json += frag
                                    if let id = toolBlocks[idx]?.id {
                                        continuation.yield(.toolArgumentsDelta(id: id, partialJSON: frag))
                                    }
                                }
                            default:
                                break
                            }

                        case "content_block_stop":
                            if let idx = event.index, let block = toolBlocks[idx] {
                                let args = parseToolArguments(block.json)
                                continuation.yield(.toolCall(
                                    ToolCall(id: block.id, name: block.name, arguments: args)
                                ))
                                toolBlocks[idx] = nil
                            }

                        case "message_delta":
                            if let reason = event.delta?.stop_reason {
                                finishReason = Self.mapFinishReason(reason)
                            }
                            if let out = event.usage?.output_tokens { outputTokens = out }

                        case "message_stop":
                            continuation.yield(.finish(
                                reason: finishReason,
                                usage: Usage(
                                    inputTokens: inputTokens,
                                    outputTokens: outputTokens,
                                    cachedInputTokens: cachedTokens
                                )
                            ))

                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        var betas = headers["anthropic-beta"].map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } ?? []
        betas.append(contentsOf: Self.betaFlags(for: request))
        if !betas.isEmpty {
            var seen = Set<String>()
            let unique = betas.filter { !$0.isEmpty && seen.insert($0).inserted }
            urlRequest.setValue(unique.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            Self.requestBody(for: request, modelID: modelID)
        )
        return urlRequest
    }

    static func betaFlags(for request: LanguageModelRequest) -> [String] {
        var flags: [String] = []
        for tool in request.providerTools(for: "anthropic") {
            guard let flag = providerToolBetas[tool.id] else { continue }
            if !flags.contains(flag) { flags.append(flag) }
        }
        return flags
    }

    static let providerToolBetas: [String: String] = [
        "anthropic.code_execution_20250522": "code-execution-2025-05-22",
        "anthropic.code_execution_20250825": "code-execution-2025-08-25",
        "anthropic.computer_20241022": "computer-use-2024-10-22",
        "anthropic.computer_20250124": "computer-use-2025-01-24",
        "anthropic.computer_20251124": "computer-use-2025-11-24",
        "anthropic.text_editor_20241022": "computer-use-2024-10-22",
        "anthropic.text_editor_20250124": "computer-use-2025-01-24",
        "anthropic.bash_20241022": "computer-use-2024-10-22",
        "anthropic.bash_20250124": "computer-use-2025-01-24",
        "anthropic.memory_20250818": "context-management-2025-06-27",
        "anthropic.web_fetch_20250910": "web-fetch-2025-09-10",
        "anthropic.web_fetch_20260209": "code-execution-web-tools-2026-02-09",
        "anthropic.web_search_20260209": "code-execution-web-tools-2026-02-09"
    ]

    static func requestBody(for request: LanguageModelRequest, modelID: String) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            "stream": .bool(true),
            "messages": .array(mapMessages(request.messages))
        ]
        if let system = systemPrompt(request.messages) { body["system"] = .string(system) }
        if let temp = request.temperature { body["temperature"] = .number(temp) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
        if !request.stopSequences.isEmpty {
            body["stop_sequences"] = .array(request.stopSequences.map { .string($0) })
        }
        var tools: [JSONValue] = request.functionTools.map {
            .object([
                "name": .string($0.name),
                "description": .string($0.description),
                "input_schema": $0.parameters
            ])
        }
        if case .json(let schema, let name, let description) = request.responseFormat {
            tools.append(.object([
                "name": .string(name),
                "description": .string(description ?? "Respond with a JSON object matching the schema."),
                "input_schema": schema
            ]))
            body["tool_choice"] = .object(["type": "tool", "name": .string(name)])
        } else if !request.functionTools.isEmpty {
            switch request.toolChoice {
            case .auto:
                break
            case .none:
                tools = []
            case .required:
                body["tool_choice"] = .object(["type": "any"])
            case .tool(let name):
                body["tool_choice"] = .object(["type": "tool", "name": .string(name)])
            }
        }
        tools.append(contentsOf: request.providerToolEntries(for: "anthropic"))
        if !tools.isEmpty { body["tools"] = .array(tools) }
        for (key, value) in reasoningFields(
            request.reasoning, modelID: modelID, maxOutputTokens: request.maxOutputTokens
        ) {
            body[key] = value
        }
        if case .object(let opts)? = request.providerOptions {
            for (k, v) in opts { body[k] = v }
        }
        return .object(body)
    }

    struct ClaudeCapabilities {
        var maxOutputTokens: Int
        var supportsAdaptiveThinking: Bool
        var supportsXhighEffort: Bool
    }

    static func modelCapabilities(_ modelID: String) -> ClaudeCapabilities {
        func has(_ names: String...) -> Bool {
            names.contains { modelID.contains($0) }
        }
        if has("claude-opus-4-8", "claude-opus-4-7", "claude-fable-5", "claude-sonnet-5") {
            return ClaudeCapabilities(
                maxOutputTokens: 128_000, supportsAdaptiveThinking: true, supportsXhighEffort: true
            )
        }
        if has("claude-sonnet-4-6", "claude-opus-4-6") {
            return ClaudeCapabilities(
                maxOutputTokens: 128_000, supportsAdaptiveThinking: true, supportsXhighEffort: false
            )
        }
        if has("claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5") {
            return ClaudeCapabilities(
                maxOutputTokens: 64_000, supportsAdaptiveThinking: false, supportsXhighEffort: false
            )
        }
        if has("claude-opus-4-1") {
            return ClaudeCapabilities(
                maxOutputTokens: 32_000, supportsAdaptiveThinking: false, supportsXhighEffort: false
            )
        }
        if has("claude-sonnet-4-") {
            return ClaudeCapabilities(
                maxOutputTokens: 64_000, supportsAdaptiveThinking: false, supportsXhighEffort: false
            )
        }
        if has("claude-opus-4-") {
            return ClaudeCapabilities(
                maxOutputTokens: 32_000, supportsAdaptiveThinking: false, supportsXhighEffort: false
            )
        }
        return ClaudeCapabilities(
            maxOutputTokens: 4096, supportsAdaptiveThinking: false, supportsXhighEffort: false
        )
    }

    static func adaptiveEffort(
        _ reasoning: ReasoningEffort, supportsXhigh: Bool
    ) -> String {
        switch reasoning {
        case .minimal, .low: return "low"
        case .xhigh: return supportsXhigh ? "xhigh" : "max"
        default: return reasoning.rawValue
        }
    }

    static func reasoningFields(
        _ reasoning: ReasoningEffort, modelID: String, maxOutputTokens: Int
    ) -> [String: JSONValue] {
        guard reasoning.isCustom else { return [:] }
        let caps = modelCapabilities(modelID)
        if reasoning == .none {
            return ["thinking": .object(["type": "disabled"])]
        }
        if caps.supportsAdaptiveThinking {
            return [
                "thinking": .object(["type": "adaptive"]),
                "output_config": .object([
                    "effort": .string(adaptiveEffort(reasoning, supportsXhigh: caps.supportsXhighEffort))
                ])
            ]
        }
        guard let budget = reasoning.budget(
            maxOutputTokens: caps.maxOutputTokens, maxBudget: caps.maxOutputTokens
        ) else { return [:] }
        return [
            "thinking": .object([
                "type": "enabled", "budget_tokens": .number(Double(budget))
            ]),
            "max_tokens": .number(Double(Swift.min(caps.maxOutputTokens, maxOutputTokens + budget)))
        ]
    }

    private static func systemPrompt(_ messages: [Message]) -> String? {
        let system = messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        return system.isEmpty ? nil : system
    }

    private static func mapMessages(_ messages: [Message]) -> [JSONValue] {
        messages.compactMap { message -> JSONValue? in
            switch message.role {
            case .system:
                return nil
            case .user:
                return .object(["role": "user", "content": .array(contentBlocks(message.content))])
            case .assistant:
                return .object(["role": "assistant", "content": .array(contentBlocks(message.content))])
            case .tool:
                return .object(["role": "user", "content": .array(contentBlocks(message.content))])
            }
        }
    }

    private static func contentBlocks(_ parts: [ContentPart]) -> [JSONValue] {
        parts.compactMap { part in
            switch part {
            case .text(let t):
                return .object(["type": "text", "text": .string(t)])
            case .image(let image):
                return .object(["type": "image", "source": imageSource(
                    data: image.data, url: image.url, mediaType: image.resolvedMediaType
                )])
            case .file(let file):
                return fileBlock(file)
            case .toolCall(let call):
                return .object([
                    "type": "tool_use",
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": call.arguments
                ])
            case .toolResult(let result):
                return .object([
                    "type": "tool_result",
                    "tool_use_id": .string(result.toolCallID),
                    "content": .string(Self.stringify(result.output)),
                    "is_error": .bool(result.isError)
                ])
            case .toolApprovalResponse:
                return nil
            }
        }
    }

    private static func imageSource(data: Data?, url: URL?, mediaType: String) -> JSONValue {
        if let url {
            return .object(["type": "url", "url": .string(url.absoluteString)])
        }
        return .object([
            "type": "base64",
            "media_type": .string(mediaType),
            "data": .string(data?.base64EncodedString() ?? "")
        ])
    }

    private static func fileBlock(_ file: FileContent) -> JSONValue? {
        if file.mediaType.hasPrefix("image/") {
            return .object(["type": "image", "source": imageSource(
                data: file.data, url: file.url, mediaType: file.mediaType
            )])
        }
        guard file.mediaType == "application/pdf" || file.mediaType == "text/plain" else {
            return nil
        }
        let source: JSONValue
        if let url = file.url {
            source = .object(["type": "url", "url": .string(url.absoluteString)])
        } else if file.mediaType == "application/pdf" {
            source = .object([
                "type": "base64",
                "media_type": "application/pdf",
                "data": .string(file.data?.base64EncodedString() ?? "")
            ])
        } else {
            source = .object([
                "type": "text",
                "media_type": "text/plain",
                "data": .string(String(decoding: file.data ?? Data(), as: UTF8.self))
            ])
        }
        var block: [String: JSONValue] = ["type": "document", "source": source]
        if let filename = file.filename { block["title"] = .string(filename) }
        return .object(block)
    }

    private static func stringify(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        guard let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    private static func mapFinishReason(_ reason: String) -> FinishReason {
        switch reason {
        case "end_turn", "stop_sequence": .stop
        case "max_tokens": .length
        case "tool_use": .toolCalls
        default: .other
        }
    }
}

private func parseToolArguments(_ json: String) -> JSONValue {
    guard let data = json.data(using: .utf8),
          let value = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return .object([:]) }
    return value
}

private struct AnthropicEvent: Decodable {
    var type: String
    var index: Int?
    var message: Message?
    var content_block: ContentBlock?
    var delta: Delta?
    var usage: Usage?

    struct Message: Decodable { var usage: Usage? }
    struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_read_input_tokens: Int?
    }
    struct ContentBlock: Decodable { var type: String?; var id: String?; var name: String? }
    struct Delta: Decodable {
        var type: String?
        var text: String?
        var thinking: String?
        var partial_json: String?
        var stop_reason: String?
    }
}

public extension AnthropicModel {
    enum Tools {
        public static func webSearch(
            version: String = "web_search_20250305",
            maxUses: Int? = nil,
            allowedDomains: [String]? = nil,
            blockedDomains: [String]? = nil,
            userLocation: JSONValue? = nil,
            name: String = "web_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": .string(version), "name": .string(name)]
            if let maxUses { args["max_uses"] = .number(Double(maxUses)) }
            if let allowedDomains { args["allowed_domains"] = .array(allowedDomains.map { .string($0) }) }
            if let blockedDomains { args["blocked_domains"] = .array(blockedDomains.map { .string($0) }) }
            if let userLocation { args["user_location"] = userLocation }
            return ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name, args: .object(args)
            )
        }

        public static func webFetch(
            version: String = "web_fetch_20250910",
            maxUses: Int? = nil,
            allowedDomains: [String]? = nil,
            blockedDomains: [String]? = nil,
            citations: JSONValue? = nil,
            maxContentTokens: Int? = nil,
            name: String = "web_fetch"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": .string(version), "name": .string(name)]
            if let maxUses { args["max_uses"] = .number(Double(maxUses)) }
            if let allowedDomains { args["allowed_domains"] = .array(allowedDomains.map { .string($0) }) }
            if let blockedDomains { args["blocked_domains"] = .array(blockedDomains.map { .string($0) }) }
            if let citations { args["citations"] = citations }
            if let maxContentTokens { args["max_content_tokens"] = .number(Double(maxContentTokens)) }
            return ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name, args: .object(args)
            )
        }

        public static func codeExecution(
            version: String = "code_execution_20250522",
            name: String = "code_execution"
        ) -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name,
                args: .object(["type": .string(version), "name": .string(name)])
            )
        }

        public static func bash(
            version: String = "bash_20250124",
            name: String = "bash"
        ) -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name,
                args: .object(["type": .string(version), "name": .string(name)])
            )
        }

        public static func textEditor(
            version: String = "text_editor_20250728",
            maxCharacters: Int? = nil
        ) -> ProviderDefinedTool {
            let toolName: String
            switch version {
            case "text_editor_20241022", "text_editor_20250124": toolName = "str_replace_editor"
            default: toolName = "str_replace_based_edit_tool"
            }
            var args: [String: JSONValue] = ["type": .string(version), "name": .string(toolName)]
            if let maxCharacters { args["max_characters"] = .number(Double(maxCharacters)) }
            return ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: toolName, args: .object(args)
            )
        }

        public static func computer(
            displayWidthPx: Int,
            displayHeightPx: Int,
            displayNumber: Int? = nil,
            version: String = "computer_20250124",
            name: String = "computer"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = [
                "type": .string(version),
                "name": .string(name),
                "display_width_px": .number(Double(displayWidthPx)),
                "display_height_px": .number(Double(displayHeightPx))
            ]
            if let displayNumber { args["display_number"] = .number(Double(displayNumber)) }
            return ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name, args: .object(args)
            )
        }

        public static func memory(
            version: String = "memory_20250818",
            name: String = "memory"
        ) -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "anthropic", id: "anthropic.\(version)", name: name,
                args: .object(["type": .string(version), "name": .string(name)])
            )
        }
    }
}
