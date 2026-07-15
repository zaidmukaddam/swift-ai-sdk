import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIModel: LanguageModel {
    public let provider = "openai"
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
        baseURL: URL? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.backend = .responses(ResponsesConfig(
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            baseURL: baseURL ?? Self.defaultBaseURL(),
            headers: Self.mergedHeaders(
                organization: organization, project: project, headers: headers
            ),
            urlSession: urlSession
        ))
    }

    public static func chat(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) -> OpenAIModel {
        OpenAIModel(modelID: modelID, chatEngine: OpenAIChatModel(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            baseURL: baseURL ?? defaultBaseURL(),
            headers: mergedHeaders(organization: organization, project: project, headers: headers),
            queryParams: [:],
            urlSession: urlSession,
            providerName: "openai"
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

    static func defaultBaseURL() -> URL {
        if var env = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"], !env.isEmpty {
            if env.hasSuffix("/") { env.removeLast() }
            if let url = URL(string: env) { return url }
        }
        return URL(string: "https://api.openai.com/v1")!
    }

    static func mergedHeaders(
        organization: String?, project: String?, headers: [String: String]
    ) -> [String: String] {
        var merged: [String: String] = [:]
        if let organization { merged["OpenAI-Organization"] = organization }
        if let project { merged["OpenAI-Project"] = project }
        for (field, value) in headers { merged[field] = value }
        return merged
    }

    static func isReasoningModel(_ modelID: String) -> Bool {
        modelID.hasPrefix("o1") || modelID.hasPrefix("o3") || modelID.hasPrefix("o4-mini")
            || (modelID.hasPrefix("gpt-5") && !modelID.hasPrefix("gpt-5-chat"))
    }

    static func supportsNonReasoningParameters(_ modelID: String) -> Bool {
        ["gpt-5.1", "gpt-5.2", "gpt-5.3", "gpt-5.4", "gpt-5.5", "gpt-5.6"]
            .contains { modelID.hasPrefix($0) }
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
                var hadRefusal = false
                var sourceCount = 0
                var finishReason: FinishReason?
                var usage = Usage()
                var logprobsContent: [JSONValue] = []

                do {
                    for try await sse in SSE.events(from: bytes) {
                        guard let data = sse.data.data(using: .utf8),
                              let event = try? JSONDecoder().decode(JSONValue.self, from: data)
                        else { continue }

                        guard let type = event["type"]?.stringValue else {
                            if event["choices"]?.arrayValue != nil {
                                throw AIError.invalidRequest(
                                    "Received a chat-completions stream on the Responses API path. "
                                    + "If your baseURL targets a chat-completions endpoint, "
                                    + "use OpenAIModel.chat(...) instead."
                                )
                            }
                            continue
                        }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                            }
                            if let logprobs = event["logprobs"]?.arrayValue {
                                logprobsContent.append(contentsOf: logprobs)
                            }

                        case "response.reasoning_summary_text.delta",
                             "response.reasoning_text.delta":
                            if let delta = event["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.reasoningDelta(delta))
                            }

                        case "response.output_item.added":
                            guard let item = event["item"],
                                  item["type"]?.stringValue == "function_call",
                                  let itemID = item["id"]?.stringValue,
                                  let name = item["name"]?.stringValue
                            else { break }
                            let callID = item["call_id"]?.stringValue ?? itemID
                            openCalls[itemID] = (callID, name, item["arguments"]?.stringValue ?? "")
                            continuation.yield(.toolCallStart(id: callID, name: name))

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
                            } else if itemType == "computer_call" {
                                let callID = item["call_id"]?.stringValue ?? itemID
                                var args: [String: JSONValue] = [:]
                                if let action = item["action"] { args["action"] = action }
                                if let safety = item["pending_safety_checks"] {
                                    args["pending_safety_checks"] = safety
                                }
                                hadFunctionCall = true
                                continuation.yield(.toolCall(ToolCall(
                                    id: callID, name: "computer_use_preview", arguments: .object(args)
                                )))
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

                        case "response.refusal.delta":
                            if let delta = event["delta"]?.stringValue, !delta.isEmpty {
                                hadRefusal = true
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.refusal.done":
                            hadRefusal = true

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
                            case "response.failed":
                                finishReason = .error
                            default:
                                let reason = event["response"]?["incomplete_details"]?["reason"]?.stringValue
                                finishReason = mapFinishReason(reason, hadFunctionCall: hadFunctionCall)
                            }

                        case "error":
                            let message = event["error"]?["message"]?.stringValue
                                ?? event["message"]?.stringValue
                                ?? "unknown stream error"
                            throw AIError.transport("OpenAI stream error: \(message)")

                        default:
                            break
                        }
                    }
                    if !logprobsContent.isEmpty {
                        continuation.yield(.providerMetadata(
                            .object(["openai": .object(["logprobs": .array(logprobsContent)])])
                        ))
                    }
                    var reason = finishReason ?? (hadFunctionCall ? .toolCalls : .stop)
                    if hadRefusal && reason == .stop { reason = .contentFilter }
                    continuation.yield(.finish(reason: reason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func mapFinishReason(_ reason: String?, hadFunctionCall: Bool) -> FinishReason {
        switch reason {
        case nil: hadFunctionCall ? .toolCalls : .stop
        case "max_output_tokens": .length
        case "content_filter": .contentFilter
        default: hadFunctionCall ? .toolCalls : .other
        }
    }

    static func serverToolName(for itemType: String) -> String? {
        switch itemType {
        case "web_search_call": return "web_search"
        case "file_search_call": return "file_search"
        case "code_interpreter_call": return "code_interpreter"
        case "image_generation_call": return "image_generation"
        case "mcp_call": return "mcp"
        default: return nil
        }
    }

    static func serverToolPayload(
        _ itemType: String, _ item: JSONValue
    ) -> (input: JSONValue, result: JSONValue) {
        switch itemType {
        case "web_search_call":
            let action = item["action"] ?? .object([:])
            return (action, action)
        case "file_search_call":
            var input: [String: JSONValue] = [:]
            if let queries = item["queries"] { input["queries"] = queries }
            var result: [String: JSONValue] = [:]
            if let results = item["results"] { result["results"] = results }
            return (.object(input), .object(result))
        case "code_interpreter_call":
            var input: [String: JSONValue] = [:]
            if let code = item["code"] { input["code"] = code }
            var result: [String: JSONValue] = [:]
            if let outputs = item["outputs"] { result["outputs"] = outputs }
            return (.object(input), .object(result))
        case "image_generation_call":
            var result: [String: JSONValue] = [:]
            if let generated = item["result"] { result["result"] = generated }
            return (.object([:]), .object(result))
        case "mcp_call":
            var input: [String: JSONValue] = [:]
            if let name = item["name"] { input["name"] = name }
            if let arguments = item["arguments"] { input["arguments"] = arguments }
            if let error = item["error"], error != .null {
                return (.object(input), .object(["error": error]))
            }
            return (.object(input), .object(["output": item["output"] ?? .null]))
        default:
            return (.object([:]), .object([:]))
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
        let reasoningModel = isReasoningModel(modelID)
        let optionsEffort = request.providerOptions?["reasoning"]?["effort"]?.stringValue
        let unifiedEffort: String? = optionsEffort == nil
            && reasoningModel && request.reasoning.isCustom
            ? request.reasoning.rawValue : nil
        let effort = optionsEffort ?? unifiedEffort
        let keepsSamplingParameters = !reasoningModel
            || (supportsNonReasoningParameters(modelID) && effort == "none")

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "stream": .bool(true),
            "max_output_tokens": .number(Double(request.maxOutputTokens)),
            "input": .array(inputItems(
                from: request.messages,
                systemRole: reasoningModel ? "developer" : "system"
            ))
        ]
        if keepsSamplingParameters {
            if let temperature = request.temperature { body["temperature"] = .number(temperature) }
            if let topP = request.topP { body["top_p"] = .number(topP) }
        }
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
        let providerTools = request.providerToolEntries(for: "openai")
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

        if let unifiedEffort {
            var reasoningObject: [String: JSONValue] = ["effort": .string(unifiedEffort)]
            if unifiedEffort != "none" { reasoningObject["summary"] = .string("detailed") }
            body["reasoning"] = .object(reasoningObject)
        }

        if case .object(let options)? = request.providerOptions {
            for (key, value) in options {
                if key == "tools", case .array(let extra) = value,
                   case .array(let existing)? = body["tools"] {
                    body["tools"] = .array(existing + extra)
                } else if case .object(let extra) = value,
                          case .object(var existing)? = body[key] {
                    for (k, v) in extra { existing[k] = v }
                    body[key] = .object(existing)
                } else {
                    body[key] = value
                }
            }
        }
        return .object(body)
    }

    static func inputItems(from messages: [Message], systemRole: String) -> [JSONValue] {
        var items: [JSONValue] = []
        let computerCallIDs = Set(messages.flatMap { message -> [String] in
            guard message.role == .assistant else { return [] }
            return message.content.compactMap { part in
                if case .toolCall(let call) = part, call.name == "computer_use_preview" {
                    return call.id
                }
                return nil
            }
        })
        for message in messages {
            switch message.role {
            case .system:
                let text = message.text
                guard !text.isEmpty else { break }
                items.append(.object([
                    "role": .string(systemRole),
                    "content": .string(text)
                ]))

            case .user:
                let content = userContentParts(message)
                guard !content.isEmpty else { break }
                items.append(.object(["role": "user", "content": .array(content)]))

            case .assistant:
                for part in message.content {
                    switch part {
                    case .text(let text) where !text.isEmpty:
                        items.append(.object([
                            "role": "assistant",
                            "content": .array([.object([
                                "type": "output_text",
                                "text": .string(text)
                            ])])
                        ]))
                    case .toolCall(let call) where call.name == "computer_use_preview":
                        items.append(.object([
                            "type": "computer_call",
                            "call_id": .string(call.id),
                            "action": call.arguments["action"] ?? .object([:]),
                            "pending_safety_checks": call.arguments["pending_safety_checks"] ?? .array([])
                        ]))
                    case .toolCall(let call):
                        let argsData = (try? JSONEncoder().encode(call.arguments)) ?? Data("{}".utf8)
                        items.append(.object([
                            "type": "function_call",
                            "call_id": .string(call.id),
                            "name": .string(call.name),
                            "arguments": .string(String(decoding: argsData, as: UTF8.self))
                        ]))
                    default:
                        break
                    }
                }

            case .tool:
                for part in message.content {
                    guard case .toolResult(let result) = part else { continue }
                    if computerCallIDs.contains(result.toolCallID) {
                        let screenshot = result.content?.lazy.compactMap { part -> String? in
                            if case .image(let image) = part {
                                return imageURLString(
                                    data: image.data, url: image.url,
                                    mediaType: image.resolvedMediaType
                                )
                            }
                            return nil
                        }.first
                        var output: [String: JSONValue] = ["type": .string("computer_screenshot")]
                        if let screenshot { output["image_url"] = .string(screenshot) }
                        items.append(.object([
                            "type": "computer_call_output",
                            "call_id": .string(result.toolCallID),
                            "output": .object(output)
                        ]))
                        continue
                    }
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
        message.content.enumerated().compactMap { index, part -> JSONValue? in
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
                if let url = file.url {
                    return .object([
                        "type": "input_file",
                        "file_url": .string(url.absoluteString)
                    ])
                }
                guard let data = file.data, file.mediaType == "application/pdf" else {
                    return nil
                }
                return .object([
                    "type": "input_file",
                    "filename": .string(file.filename ?? "part-\(index).pdf"),
                    "file_data": .string(
                        "data:application/pdf;base64,\(data.base64EncodedString())"
                    )
                ])
            default:
                return nil
            }
        }
    }

    private static func imageURLString(data: Data?, url: URL?, mediaType: String) -> String {
        url?.absoluteString ?? "data:\(mediaType);base64,\(data?.base64EncodedString() ?? "")"
    }
}

public extension OpenAIModel {
    enum Tools {
        public static func webSearch(
            allowedDomains: [String]? = nil,
            externalWebAccess: Bool? = nil,
            searchContextSize: String? = nil,
            userLocation: JSONValue? = nil,
            name: String = "web_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": "web_search"]
            if let allowedDomains {
                args["filters"] = .object(["allowed_domains": .array(allowedDomains.map { .string($0) })])
            }
            if let externalWebAccess { args["external_web_access"] = .bool(externalWebAccess) }
            if let searchContextSize { args["search_context_size"] = .string(searchContextSize) }
            if let userLocation { args["user_location"] = userLocation }
            return ProviderDefinedTool(
                provider: "openai", id: "openai.web_search", name: name, args: .object(args)
            )
        }

        public static func webSearchPreview(
            searchContextSize: String? = nil,
            userLocation: JSONValue? = nil,
            name: String = "web_search_preview"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = ["type": "web_search_preview"]
            if let searchContextSize { args["search_context_size"] = .string(searchContextSize) }
            if let userLocation { args["user_location"] = userLocation }
            return ProviderDefinedTool(
                provider: "openai", id: "openai.web_search_preview", name: name, args: .object(args)
            )
        }

        public static func fileSearch(
            vectorStoreIds: [String],
            maxNumResults: Int? = nil,
            filters: JSONValue? = nil,
            name: String = "file_search"
        ) -> ProviderDefinedTool {
            var args: [String: JSONValue] = [
                "type": "file_search",
                "vector_store_ids": .array(vectorStoreIds.map { .string($0) })
            ]
            if let maxNumResults { args["max_num_results"] = .number(Double(maxNumResults)) }
            if let filters { args["filters"] = filters }
            return ProviderDefinedTool(
                provider: "openai", id: "openai.file_search", name: name, args: .object(args)
            )
        }

        public static func codeInterpreter(
            fileIds: [String]? = nil,
            name: String = "code_interpreter"
        ) -> ProviderDefinedTool {
            var container: [String: JSONValue] = ["type": "auto"]
            if let fileIds { container["file_ids"] = .array(fileIds.map { .string($0) }) }
            return ProviderDefinedTool(
                provider: "openai", id: "openai.code_interpreter", name: name,
                args: .object(["type": "code_interpreter", "container": .object(container)])
            )
        }

        public static func computerUse(
            displayWidth: Int,
            displayHeight: Int,
            environment: String = "browser",
            name: String = "computer_use_preview"
        ) -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "openai", id: "openai.computer_use_preview", name: name,
                args: .object([
                    "type": "computer_use_preview",
                    "display_width": .number(Double(displayWidth)),
                    "display_height": .number(Double(displayHeight)),
                    "environment": .string(environment)
                ])
            )
        }
    }
}
