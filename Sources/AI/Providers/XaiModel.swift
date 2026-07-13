import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct XaiModel: LanguageModel {
    public let provider = "xai"
    public let modelID: String

    private enum Backend: Sendable {
        case responses(ResponsesConfig)
        case chat(OpenAIChatModel)
    }

    struct ResponsesConfig: Sendable {
        var apiKey: String
        var baseURL: URL
        var headers: [String: String]
        var urlSession: URLSession
    }

    private let backend: Backend

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.backend = .responses(ResponsesConfig(
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession
        ))
    }

    public static func chat(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) -> XaiModel {
        XaiModel(modelID: modelID, chatEngine: OpenAIChatModel(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            queryParams: [:],
            urlSession: urlSession,
            providerName: "xai"
        ))
    }

    private init(modelID: String, chatEngine: OpenAIChatModel) {
        self.modelID = modelID
        self.backend = .chat(chatEngine)
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        switch backend {
        case .chat(let engine):
            return try await engine.stream(request)
        case .responses(let config):
            return try await Self.streamResponses(config, modelID: modelID, request: request)
        }
    }

    public struct SearchParameters: Sendable {
        public enum Mode: String, Sendable {
            case auto, on, off
        }

        public enum SearchSource: Sendable {
            case web(country: String? = nil, excludedWebsites: [String]? = nil,
                     allowedWebsites: [String]? = nil, safeSearch: Bool? = nil)
            case x(includedHandles: [String]? = nil, excludedHandles: [String]? = nil,
                   postFavoriteCount: Int? = nil, postViewCount: Int? = nil)
            case news(country: String? = nil, excludedWebsites: [String]? = nil,
                      safeSearch: Bool? = nil)
        }

        public var mode: Mode
        public var returnCitations: Bool?
        public var fromDate: String?
        public var toDate: String?
        public var maxSearchResults: Int?
        public var sources: [SearchSource]

        public init(
            mode: Mode = .auto,
            returnCitations: Bool? = nil,
            fromDate: String? = nil,
            toDate: String? = nil,
            maxSearchResults: Int? = nil,
            sources: [SearchSource] = []
        ) {
            self.mode = mode
            self.returnCitations = returnCitations
            self.fromDate = fromDate
            self.toDate = toDate
            self.maxSearchResults = maxSearchResults
            self.sources = sources
        }

        public var providerOptions: JSONValue {
            .object(["search_parameters": jsonValue])
        }

        public var jsonValue: JSONValue {
            var object: [String: JSONValue] = ["mode": .string(mode.rawValue)]
            if let returnCitations { object["return_citations"] = .bool(returnCitations) }
            if let fromDate { object["from_date"] = .string(fromDate) }
            if let toDate { object["to_date"] = .string(toDate) }
            if let maxSearchResults {
                object["max_search_results"] = .number(Double(maxSearchResults))
            }
            if !sources.isEmpty {
                object["sources"] = .array(sources.map { source in
                    switch source {
                    case .web(let country, let excluded, let allowed, let safeSearch):
                        var web: [String: JSONValue] = ["type": "web"]
                        if let country { web["country"] = .string(country) }
                        if let excluded {
                            web["excluded_websites"] = .array(excluded.map { .string($0) })
                        }
                        if let allowed {
                            web["allowed_websites"] = .array(allowed.map { .string($0) })
                        }
                        if let safeSearch { web["safe_search"] = .bool(safeSearch) }
                        return .object(web)
                    case .x(let included, let excluded, let favorites, let views):
                        var x: [String: JSONValue] = ["type": "x"]
                        if let included {
                            x["included_x_handles"] = .array(included.map { .string($0) })
                        }
                        if let excluded {
                            x["excluded_x_handles"] = .array(excluded.map { .string($0) })
                        }
                        if let favorites { x["post_favorite_count"] = .number(Double(favorites)) }
                        if let views { x["post_view_count"] = .number(Double(views)) }
                        return .object(x)
                    case .news(let country, let excluded, let safeSearch):
                        var news: [String: JSONValue] = ["type": "news"]
                        if let country { news["country"] = .string(country) }
                        if let excluded {
                            news["excluded_websites"] = .array(excluded.map { .string($0) })
                        }
                        if let safeSearch { news["safe_search"] = .bool(safeSearch) }
                        return .object(news)
                    }
                })
            }
            return .object(object)
        }
    }

    static func serverToolName(for itemType: String) -> String? {
        switch itemType {
        case "web_search_call": return "web_search"
        case "x_search_call": return "x_search"
        case "code_interpreter_call": return "code_interpreter"
        case "code_execution_call": return "code_execution"
        default: return nil
        }
    }

    static func mergeSearchCallPayload(_ item: JSONValue) -> JSONValue {
        if case .object(let action)? = item["action"], !action.isEmpty {
            return .object(action)
        }
        if let input = item["input"]?.stringValue, !input.isEmpty,
           let data = input.data(using: .utf8),
           case .object(let parsed)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return .object(parsed)
        }
        return .object([:])
    }

    static func codeInterpreterResult(_ item: JSONValue) -> JSONValue {
        let stdout = (item["outputs"]?.arrayValue ?? [])
            .compactMap { output -> String? in
                guard output["type"]?.stringValue == "logs" else { return nil }
                return output["logs"]?.stringValue
            }
            .joined(separator: "\n")
        var result: [String: JSONValue] = ["output": .string(stdout)]
        if let error = item["error"], error != .null { result["error"] = error }
        return .object(result)
    }

    static func serverToolPayload(_ itemType: String, _ item: JSONValue) -> (input: JSONValue, result: JSONValue) {
        switch itemType {
        case "web_search_call", "x_search_call":
            let payload = mergeSearchCallPayload(item)
            return (payload, payload)
        case "code_interpreter_call", "code_execution_call":
            let input: JSONValue = item["code"]?.stringValue.map { .object(["code": .string($0)]) }
                ?? .object([:])
            return (input, codeInterpreterResult(item))
        default:
            return (.object([:]), .object([:]))
        }
    }

    private static func streamResponses(
        _ config: ResponsesConfig,
        modelID: String,
        request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let urlRequest = try buildResponsesRequest(config, modelID: modelID, request: request)
        let (bytes, response) = try await config.urlSession.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw AIError.http(status: http.statusCode, body: body)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var openCalls: [String: (callID: String, name: String, arguments: String)] = [:]
                var hadFunctionCall = false
                var sourceCount = 0
                var finishReason: FinishReason?
                var usage = Usage()

                do {
                    for try await sse in SSE.events(from: bytes) {
                        guard let data = sse.data.data(using: .utf8),
                              let event = try? JSONDecoder().decode(JSONValue.self, from: data),
                              let type = event["type"]?.stringValue
                        else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.reasoning_text.delta",
                             "response.reasoning_summary_text.delta":
                            if let delta = event["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.reasoningDelta(delta))
                            }

                        case "response.output_item.added":
                            guard let item = event["item"],
                                  let itemType = item["type"]?.stringValue,
                                  let itemID = item["id"]?.stringValue
                            else { break }
                            if itemType == "function_call", let name = item["name"]?.stringValue {
                                let callID = item["call_id"]?.stringValue ?? itemID
                                openCalls[itemID] = (callID, name, item["arguments"]?.stringValue ?? "")
                                continuation.yield(.toolCallStart(id: callID, name: name))
                            } else if let toolName = Self.serverToolName(for: itemType) {
                                continuation.yield(.toolCallStart(id: itemID, name: toolName))
                            }

                        case "response.function_call_arguments.delta":
                            guard let itemID = event["item_id"]?.stringValue,
                                  let delta = event["delta"]?.stringValue,
                                  var call = openCalls[itemID]
                            else { break }
                            call.arguments += delta
                            openCalls[itemID] = call
                            continuation.yield(.toolArgumentsDelta(id: call.callID, partialJSON: delta))

                        case "response.output_item.done":
                            guard let item = event["item"],
                                  let itemType = item["type"]?.stringValue,
                                  let itemID = item["id"]?.stringValue
                            else { break }
                            if itemType == "function_call" {
                                let buffered = openCalls.removeValue(forKey: itemID)
                                let callID = item["call_id"]?.stringValue ?? buffered?.callID ?? itemID
                                let name = item["name"]?.stringValue ?? buffered?.name ?? ""
                                let argsText = item["arguments"]?.stringValue ?? buffered?.arguments ?? ""
                                let arguments = (try? JSONDecoder().decode(
                                    JSONValue.self, from: Data(argsText.utf8))) ?? .object([:])
                                hadFunctionCall = true
                                continuation.yield(.toolCall(
                                    ToolCall(id: callID, name: name, arguments: arguments)
                                ))
                            } else if let toolName = Self.serverToolName(for: itemType) {
                                let (input, result) = Self.serverToolPayload(itemType, item)
                                continuation.yield(.toolCall(ToolCall(
                                    id: itemID, name: toolName,
                                    arguments: input, providerExecuted: true
                                )))
                                continuation.yield(.toolResult(ToolResult(
                                    toolCallID: itemID, name: toolName, output: result
                                )))
                            }

                        case "response.output_text.annotation.added":
                            guard let annotation = event["annotation"],
                                  annotation["type"]?.stringValue == "url_citation",
                                  let url = annotation["url"]?.stringValue
                            else { break }
                            continuation.yield(.source(Source(
                                id: "source-\(sourceCount)",
                                url: url,
                                title: annotation["title"]?.stringValue
                            )))
                            sourceCount += 1

                        case "response.completed", "response.incomplete", "response.failed":
                            if let u = event["response"]?["usage"] {
                                usage = Usage(
                                    inputTokens: u["input_tokens"]?.intValue ?? 0,
                                    outputTokens: u["output_tokens"]?.intValue ?? 0,
                                    cachedInputTokens:
                                        u["input_tokens_details"]?["cached_tokens"]?.intValue,
                                    reasoningTokens:
                                        u["output_tokens_details"]?["reasoning_tokens"]?.intValue
                                )
                            }
                            switch type {
                            case "response.incomplete":
                                let reason = event["response"]?["incomplete_details"]?["reason"]?.stringValue
                                finishReason = reason == "max_output_tokens" ? .length : .other
                            case "response.failed":
                                finishReason = .error
                            default:
                                finishReason = hadFunctionCall ? .toolCalls : .stop
                            }

                        default:
                            break
                        }
                    }
                    continuation.yield(.finish(
                        reason: finishReason ?? (hadFunctionCall ? .toolCalls : .stop),
                        usage: usage
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func buildResponsesRequest(
        _ config: ResponsesConfig,
        modelID: String,
        request: LanguageModelRequest
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        if !config.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in config.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            responsesBody(for: request, modelID: modelID)
        )
        return urlRequest
    }

    static func responsesBody(for request: LanguageModelRequest, modelID: String) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "stream": .bool(true),
            "max_output_tokens": .number(Double(request.maxOutputTokens)),
            "input": .array(inputItems(from: request.messages))
        ]
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }

        if case .jsonNoSchema = request.responseFormat {
            body["text"] = .object(["format": .object(["type": "json_object"])])
        }
        if case .json(let schema, let name, let description) = request.responseFormat {
            var format: [String: JSONValue] = [
                "type": "json_schema",
                "strict": .bool(true),
                "name": .string(name),
                "schema": schema
            ]
            if let description { format["description"] = .string(description) }
            body["text"] = .object(["format": .object(format)])
        }

        let functionTools = request.functionTools
        let providerTools = request.providerToolEntries(for: "xai")
        if !functionTools.isEmpty || !providerTools.isEmpty {
            var toolsArray: [JSONValue] = functionTools.map {
                .object([
                    "type": "function",
                    "name": .string($0.name),
                    "description": .string($0.description),
                    "parameters": $0.parameters
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
                body["tool_choice"] = .object(["type": "function", "name": .string(name)])
            }
        }

        if request.reasoning.isCustom,
           modelID.range(
               of: #"^grok-4\.20(-\d{4})?-(non-)?reasoning$"#, options: .regularExpression
           ) == nil {
            let effort: String
            switch request.reasoning {
            case .minimal: effort = "low"
            case .xhigh: effort = "high"
            default: effort = request.reasoning.rawValue
            }
            body["reasoning"] = .object(["effort": .string(effort)])
        }

        if case .object(let options)? = request.providerOptions {
            for (key, value) in options {
                if key == "tools", case .array(let extra) = value,
                   case .array(let existing)? = body["tools"] {
                    body["tools"] = .array(existing + extra)
                } else {
                    body[key] = value
                }
            }
        }
        return .object(body)
    }

    static func inputItems(from messages: [Message]) -> [JSONValue] {
        var items: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system:
                let text = message.text
                guard !text.isEmpty else { break }
                items.append(.object([
                    "role": "system",
                    "content": .array([.object(["type": "input_text", "text": .string(text)])])
                ]))

            case .user:
                let content = userContentParts(message)
                guard !content.isEmpty else { break }
                items.append(.object(["role": "user", "content": .array(content)]))

            case .assistant:
                for part in message.content {
                    switch part {
                    case .text(let text) where !text.isEmpty:
                        items.append(.object(["role": "assistant", "content": .string(text)]))
                    case .toolCall(let call):
                        let argsData = (try? JSONEncoder().encode(call.arguments)) ?? Data("{}".utf8)
                        items.append(.object([
                            "type": "function_call",
                            "id": .string(call.id),
                            "call_id": .string(call.id),
                            "name": .string(call.name),
                            "arguments": .string(String(decoding: argsData, as: UTF8.self)),
                            "status": "completed"
                        ]))
                    default:
                        break
                    }
                }

            case .tool:
                for part in message.content {
                    guard case .toolResult(let result) = part else { continue }
                    let output: String
                    if case .string(let s) = result.output {
                        output = s
                    } else {
                        let data = (try? JSONEncoder().encode(result.output)) ?? Data()
                        output = String(decoding: data, as: UTF8.self)
                    }
                    items.append(.object([
                        "type": "function_call_output",
                        "call_id": .string(result.toolCallID),
                        "output": .string(output)
                    ]))
                }
            }
        }
        return items
    }

    private static func userContentParts(_ message: Message) -> [JSONValue] {
        message.content.compactMap { part -> JSONValue? in
            switch part {
            case .text(let text) where !text.isEmpty:
                return .object(["type": "input_text", "text": .string(text)])
            case .image(let image):
                return .object([
                    "type": "input_image",
                    "image_url": .string(imageURLString(
                        data: image.data, url: image.url, mediaType: image.resolvedMediaType
                    ))
                ])
            case .file(let file) where file.mediaType.hasPrefix("image/"):
                return .object([
                    "type": "input_image",
                    "image_url": .string(imageURLString(
                        data: file.data, url: file.url, mediaType: file.mediaType
                    ))
                ])
            case .file(let file):
                guard let url = file.url else { return nil }
                return .object(["type": "input_file", "file_url": .string(url.absoluteString)])
            default:
                return nil
            }
        }
    }

    private static func imageURLString(data: Data?, url: URL?, mediaType: String) -> String {
        url?.absoluteString ?? "data:\(mediaType);base64,\(data?.base64EncodedString() ?? "")"
    }
}

public extension XaiModel {
    enum Tools {
        static func webSearch(
            allowedDomains: [String]? = nil,
            excludedDomains: [String]? = nil,
            enableImageSearch: Bool? = nil,
            enableImageUnderstanding: Bool? = nil,
            name: String = "web_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": "web_search"]
            if let allowedDomains { args["allowed_domains"] = .array(allowedDomains.map { .string($0) }) }
            if let excludedDomains { args["excluded_domains"] = .array(excludedDomains.map { .string($0) }) }
            if let enableImageSearch { args["enable_image_search"] = .bool(enableImageSearch) }
            if let enableImageUnderstanding {
                args["enable_image_understanding"] = .bool(enableImageUnderstanding)
            }
            return ProviderDefinedTool(
                provider: "xai", id: "xai.web_search", name: name, args: .object(args)
            )
        }

        static func xSearch(
            allowedXHandles: [String]? = nil,
            excludedXHandles: [String]? = nil,
            fromDate: String? = nil,
            toDate: String? = nil,
            enableImageUnderstanding: Bool? = nil,
            enableVideoUnderstanding: Bool? = nil,
            name: String = "x_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": "x_search"]
            if let allowedXHandles { args["allowed_x_handles"] = .array(allowedXHandles.map { .string($0) }) }
            if let excludedXHandles { args["excluded_x_handles"] = .array(excludedXHandles.map { .string($0) }) }
            if let fromDate { args["from_date"] = .string(fromDate) }
            if let toDate { args["to_date"] = .string(toDate) }
            if let enableImageUnderstanding {
                args["enable_image_understanding"] = .bool(enableImageUnderstanding)
            }
            if let enableVideoUnderstanding {
                args["enable_video_understanding"] = .bool(enableVideoUnderstanding)
            }
            return ProviderDefinedTool(
                provider: "xai", id: "xai.x_search", name: name, args: .object(args)
            )
        }

        static func codeExecution(name: String = "code_interpreter") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "xai", id: "xai.code_execution", name: name,
                args: .object(["type": "code_interpreter"])
            )
        }

        static func fileSearch(
            vectorStoreIds: [String],
            maxNumResults: Int? = nil,
            name: String = "file_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = [
                "type": "file_search",
                "vector_store_ids": .array(vectorStoreIds.map { .string($0) })
            ]
            if let maxNumResults { args["max_num_results"] = .number(Double(maxNumResults)) }
            return ProviderDefinedTool(
                provider: "xai", id: "xai.file_search", name: name, args: .object(args)
            )
        }

        static func mcpServer(
            serverUrl: String,
            serverLabel: String? = nil,
            serverDescription: String? = nil,
            allowedTools: [String]? = nil,
            headers: [String: String]? = nil,
            authorization: String? = nil,
            name: String = "mcp"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": "mcp", "server_url": .string(serverUrl)]
            if let serverLabel { args["server_label"] = .string(serverLabel) }
            if let serverDescription { args["server_description"] = .string(serverDescription) }
            if let allowedTools { args["allowed_tools"] = .array(allowedTools.map { .string($0) }) }
            if let headers {
                args["headers"] = .object(headers.mapValues { .string($0) })
            }
            if let authorization { args["authorization"] = .string(authorization) }
            return ProviderDefinedTool(
                provider: "xai", id: "xai.mcp", name: name, args: .object(args)
            )
        }

        static func viewImage(name: String = "view_image") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "xai", id: "xai.view_image", name: name,
                args: .object(["type": "view_image"])
            )
        }

        static func viewXVideo(name: String = "view_x_video") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "xai", id: "xai.view_x_video", name: name,
                args: .object(["type": "view_x_video"])
            )
        }
    }
}
