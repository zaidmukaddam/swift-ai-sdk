import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct BedrockModel: LanguageModel {
    public let provider = "bedrock"
    public let modelID: String

    private let apiKey: String
    private let region: String
    private let accessKeyID: String
    private let secretAccessKey: String
    private let sessionToken: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        region: String = "us-east-1",
        accessKeyID: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        baseURL: URL? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        let env = ProcessInfo.processInfo.environment
        let resolvedKey = apiKey ?? env["AWS_BEARER_TOKEN_BEDROCK"] ?? ""
        self.apiKey = resolvedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region
        self.accessKeyID = accessKeyID ?? env["AWS_ACCESS_KEY_ID"] ?? ""
        self.secretAccessKey = secretAccessKey ?? env["AWS_SECRET_ACCESS_KEY"] ?? ""
        self.sessionToken = sessionToken ?? env["AWS_SESSION_TOKEN"] ?? ""
        self.baseURL = baseURL
            ?? URL(string: "https://bedrock-runtime.\(region).amazonaws.com")
            ?? URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com")!
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

        let isForcedJSON: Bool
        if case .json = request.responseFormat { isForcedJSON = true } else { isForcedJSON = false }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var toolBlocks: [Int: (id: String, name: String, type: String?, json: String)] = [:]
                var stopReason: String?
                var isJsonResponseFromTool = false
                var usage = Usage()

                do {
                    for try await message in AWSEventStream.messages(from: bytes) {
                        let messageType = message.headers[":message-type"]
                        if messageType == "exception" {
                            let kind = message.headers[":exception-type"] ?? "exception"
                            throw AIError.transport(
                                "bedrock stream \(kind): \(String(decoding: message.payload, as: UTF8.self))"
                            )
                        }
                        guard messageType == "event",
                              let eventType = message.headers[":event-type"],
                              let payload = try? JSONDecoder().decode(JSONValue.self, from: message.payload)
                        else { continue }

                        switch eventType {
                        case "contentBlockStart":
                            guard let toolUse = payload["start"]?["toolUse"],
                                  let id = toolUse["toolUseId"]?.stringValue,
                                  let name = toolUse["name"]?.stringValue
                            else { break }
                            let index = payload["contentBlockIndex"]?.intValue ?? 0
                            let type = toolUse["type"]?.stringValue
                            toolBlocks[index] = (id: id, name: name, type: type, json: "")
                            if !(isForcedJSON && name == Self.jsonToolName) {
                                continuation.yield(.toolCallStart(id: id, name: name))
                            }

                        case "contentBlockDelta":
                            guard let delta = payload["delta"] else { break }
                            let index = payload["contentBlockIndex"]?.intValue ?? 0
                            if let text = delta["text"]?.stringValue {
                                continuation.yield(.textDelta(text))
                            } else if let fragment = delta["toolUse"]?["input"]?.stringValue {
                                toolBlocks[index]?.json += fragment
                                if let block = toolBlocks[index],
                                   !(isForcedJSON && block.name == Self.jsonToolName) {
                                    continuation.yield(.toolArgumentsDelta(
                                        id: block.id, partialJSON: fragment
                                    ))
                                }
                            } else if let thinking = delta["reasoningContent"]?["text"]?.stringValue {
                                continuation.yield(.reasoningDelta(thinking))
                            }

                        case "contentBlockStop":
                            let index = payload["contentBlockIndex"]?.intValue ?? 0
                            guard let block = toolBlocks.removeValue(forKey: index) else { break }
                            let jsonText = block.json.isEmpty ? "{}" : block.json
                            if isForcedJSON && block.name == Self.jsonToolName {
                                isJsonResponseFromTool = true
                                continuation.yield(.textDelta(jsonText))
                            } else {
                                continuation.yield(.toolCall(ToolCall(
                                    id: block.id,
                                    name: block.name,
                                    arguments: Self.parseArguments(jsonText),
                                    providerExecuted: block.type != nil
                                )))
                            }

                        case "messageStop":
                            stopReason = payload["stopReason"]?.stringValue

                        case "metadata":
                            if let u = payload["usage"] {
                                usage = Usage(
                                    inputTokens: (u["inputTokens"]?.intValue ?? 0)
                                        + (u["cacheReadInputTokens"]?.intValue ?? 0)
                                        + (u["cacheWriteInputTokens"]?.intValue ?? 0),
                                    outputTokens: u["outputTokens"]?.intValue ?? 0,
                                    cachedInputTokens: u["cacheReadInputTokens"]?.intValue
                                )
                            }
                            var bedrock: [String: JSONValue] = [:]
                            if let trace = payload["trace"] { bedrock["trace"] = trace }
                            if let cacheWrite = payload["usage"]?["cacheWriteInputTokens"] {
                                bedrock["cacheWriteInputTokens"] = cacheWrite
                            }
                            if !bedrock.isEmpty {
                                continuation.yield(.providerMetadata(.object(["bedrock": .object(bedrock)])))
                            }

                        case "internalServerException", "modelStreamErrorException",
                             "throttlingException", "validationException":
                            throw AIError.transport(
                                "bedrock stream \(eventType): \(String(decoding: message.payload, as: UTF8.self))"
                            )

                        default:
                            break
                        }
                    }
                    continuation.yield(.finish(
                        reason: Self.mapStopReason(
                            stopReason, isJsonResponseFromTool: isJsonResponseFromTool
                        ),
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

    static let jsonToolName = "json"

    func buildURLRequest(_ request: LanguageModelRequest) throws -> URLRequest {
        guard let url = URL(
            string: "\(baseURL.absoluteString)/model/\(Self.encodeModelID(modelID))/converse-stream"
        ) else {
            throw AIError.invalidRequest("could not build Bedrock URL for model \(modelID)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let body = try JSONEncoder().encode(Self.requestBody(for: request, modelID: modelID))
        urlRequest.httpBody = body

        if !accessKeyID.isEmpty && !secretAccessKey.isEmpty {
            try signSigV4(&urlRequest, url: url, body: body)
        } else if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    func signSigV4(_ urlRequest: inout URLRequest, url: URL, body: Data) throws {
        #if canImport(CryptoKit)
        guard let host = url.host else {
            throw AIError.invalidRequest("Bedrock URL has no host to sign")
        }
        let amzFormatter = DateFormatter()
        amzFormatter.locale = Locale(identifier: "en_US_POSIX")
        amzFormatter.timeZone = TimeZone(identifier: "UTC")
        amzFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = amzFormatter.string(from: Date())
        let dateStamp = String(amzDate.prefix(8))

        let canonicalURI = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedPath ?? url.path
        let payloadHash = Self.sha256Hex(body)

        var canonicalHeaders = "content-type:application/json\n"
        canonicalHeaders += "host:\(host)\n"
        canonicalHeaders += "x-amz-date:\(amzDate)\n"
        var signedHeaders = "content-type;host;x-amz-date"
        if !sessionToken.isEmpty {
            canonicalHeaders += "x-amz-security-token:\(sessionToken)\n"
            signedHeaders += ";x-amz-security-token"
        }

        let canonicalRequest = [
            "POST", canonicalURI, "", canonicalHeaders, signedHeaders, payloadHash
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/bedrock/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", amzDate, scope, Self.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        var signingKey = Data("AWS4\(secretAccessKey)".utf8)
        for part in [dateStamp, region, "bedrock", "aws4_request"] {
            signingKey = Self.hmac(signingKey, part)
        }
        let signature = Self.hmac(signingKey, stringToSign)
            .map { String(format: "%02x", $0) }.joined()

        urlRequest.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if !sessionToken.isEmpty {
            urlRequest.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        }
        urlRequest.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), "
                + "SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        #else
        throw AIError.invalidRequest("Bedrock SigV4 signing requires CryptoKit")
        #endif
    }

    #if canImport(CryptoKit)
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(_ key: Data, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }
    #endif

    private static let modelIDAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    static func encodeModelID(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: modelIDAllowed) ?? id
    }

    static func requestBody(for request: LanguageModelRequest, modelID: String = "") -> JSONValue {
        let mapped = mapMessages(request.messages)
        var body: [String: JSONValue] = ["messages": .array(mapped.turns)]
        if !mapped.system.isEmpty { body["system"] = .array(mapped.system) }

        var inference: [String: JSONValue] = [
            "maxTokens": .number(Double(request.maxOutputTokens))
        ]
        if let temperature = request.temperature {
            inference["temperature"] = .number(min(max(temperature, 0), 1))
        }
        if let topP = request.topP { inference["topP"] = .number(topP) }
        if !request.stopSequences.isEmpty {
            inference["stopSequences"] = .array(request.stopSequences.map { .string($0) })
        }
        body["inferenceConfig"] = .object(inference)
        if let topK = request.topK {
            body["additionalModelRequestFields"] = .object([
                "top_k": .number(Double(topK))
            ])
        }

        var tools: [JSONValue] = request.tools.map {
            .object(["toolSpec": .object([
                "name": .string($0.name),
                "description": .string($0.description),
                "inputSchema": .object(["json": $0.parameters])
            ])])
        }
        var toolChoice: JSONValue?
        if case .json(let schema, _, _) = request.responseFormat {
            tools.append(.object(["toolSpec": .object([
                "name": .string(jsonToolName),
                "description": "Respond with a JSON object.",
                "inputSchema": .object(["json": schema])
            ])]))
            toolChoice = .object(["any": .object([:])])
        } else if !request.tools.isEmpty {
            switch request.toolChoice {
            case .auto:
                break
            case .none:
                tools = []
            case .required:
                toolChoice = .object(["any": .object([:])])
            case .tool(let name):
                tools = tools.filter { $0["toolSpec"]?["name"]?.stringValue == name }
                toolChoice = .object(["tool": .object(["name": .string(name)])])
            }
        }
        if !tools.isEmpty {
            var toolConfig: [String: JSONValue] = ["tools": .array(tools)]
            if let toolChoice { toolConfig["toolChoice"] = toolChoice }
            body["toolConfig"] = .object(toolConfig)
        }

        applyReasoning(request.reasoning, modelID: modelID, to: &body)

        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }
        return .object(body)
    }

    static func bedrockEffort(_ reasoning: ReasoningEffort) -> String {
        switch reasoning {
        case .minimal, .low: return "low"
        case .xhigh: return "max"
        default: return reasoning.rawValue
        }
    }

    static func applyReasoning(
        _ reasoning: ReasoningEffort, modelID: String, to body: inout [String: JSONValue]
    ) {
        guard reasoning.isCustom else { return }
        var extraFields = body["additionalModelRequestFields"]?.objectValue ?? [:]

        if modelID.contains("anthropic.") {
            let caps = AnthropicModel.modelCapabilities(modelID)
            if reasoning == .none {
                return
            }
            if caps.supportsAdaptiveThinking {
                extraFields["thinking"] = .object(["type": "adaptive"])
                extraFields["output_config"] = .object([
                    "effort": .string(bedrockEffort(reasoning))
                ])
            } else if let budget = reasoning.budget(
                maxOutputTokens: caps.maxOutputTokens, maxBudget: caps.maxOutputTokens
            ) {
                extraFields["thinking"] = .object([
                    "type": "enabled", "budget_tokens": .number(Double(budget))
                ])
                if var inference = body["inferenceConfig"]?.objectValue {
                    let maxTokens = inference["maxTokens"]?.intValue ?? 4096
                    inference["maxTokens"] = .number(Double(maxTokens + budget))
                    body["inferenceConfig"] = .object(inference)
                }
            }
        } else if modelID.contains("openai.") {
            extraFields["reasoning_effort"] = .string(bedrockEffort(reasoning))
        } else if reasoning != .none {
            extraFields["reasoningConfig"] = .object([
                "maxReasoningEffort": .string(bedrockEffort(reasoning))
            ])
        } else {
            return
        }
        body["additionalModelRequestFields"] = .object(extraFields)
    }

    static func mapMessages(_ messages: [Message]) -> (system: [JSONValue], turns: [JSONValue]) {
        var system: [JSONValue] = []
        var turns: [(role: String, blocks: [JSONValue])] = []

        func append(_ role: String, _ blocks: [JSONValue]) {
            guard !blocks.isEmpty else { return }
            if turns.isEmpty || turns[turns.count - 1].role != role {
                turns.append((role: role, blocks: blocks))
            } else {
                turns[turns.count - 1].blocks.append(contentsOf: blocks)
            }
        }

        for message in messages {
            switch message.role {
            case .system:
                let text = message.text
                guard !text.isEmpty else { break }
                system.append(.object(["text": .string(text)]))

            case .user:
                append("user", message.content.compactMap { part in
                    switch part {
                    case .text(let text):
                        return text.isEmpty ? nil : .object(["text": .string(text)])
                    case .image(let image):
                        guard let data = image.data else { return nil }
                        return .object(["image": .object([
                            "format": .string(subtype(of: image.resolvedMediaType)),
                            "source": .object(["bytes": .string(data.base64EncodedString())])
                        ])])
                    case .file(let file):
                        guard let data = file.data else { return nil }
                        if file.mediaType.hasPrefix("image/") {
                            return .object(["image": .object([
                                "format": .string(subtype(of: file.mediaType)),
                                "source": .object(["bytes": .string(data.base64EncodedString())])
                            ])])
                        }
                        return .object(["document": .object([
                            "format": .string(subtype(of: file.mediaType)),
                            "name": .string(file.filename ?? "document"),
                            "source": .object(["bytes": .string(data.base64EncodedString())])
                        ])])
                    case .toolCall, .toolResult, .toolApprovalResponse:
                        return nil
                    }
                })

            case .tool:
                append("user", message.content.compactMap { part in
                    guard case .toolResult(let result) = part else { return nil }
                    return .object(["toolResult": .object([
                        "toolUseId": .string(result.toolCallID),
                        "content": .array([.object(["text": .string(stringify(result.output))])])
                    ])])
                })

            case .assistant:
                append("assistant", message.content.compactMap { part in
                    switch part {
                    case .text(let text):
                        return text.isEmpty ? nil : .object(["text": .string(text)])
                    case .toolCall(let call):
                        let input: JSONValue
                        if case .object = call.arguments {
                            input = call.arguments
                        } else {
                            input = .object(["rawInvalidInput": call.arguments])
                        }
                        return .object(["toolUse": .object([
                            "toolUseId": .string(call.id),
                            "name": .string(call.name),
                            "input": input
                        ])])
                    case .toolResult, .image, .file, .toolApprovalResponse:
                        return nil
                    }
                })
            }
        }

        if let last = turns.indices.last, turns[last].role == "assistant",
           let blockIndex = turns[last].blocks.indices.last,
           case .object(var block) = turns[last].blocks[blockIndex],
           let text = block["text"]?.stringValue {
            block["text"] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
            turns[last].blocks[blockIndex] = .object(block)
        }

        return (
            system,
            turns.map { .object(["role": .string($0.role), "content": .array($0.blocks)]) }
        )
    }

    private static func subtype(of mediaType: String) -> String {
        String(mediaType.split(separator: "/").last ?? "octet-stream")
    }

    private static func stringify(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        guard let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    private static func parseArguments(_ json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .object([:]) }
        return value
    }

    static func mapStopReason(
        _ raw: String?, isJsonResponseFromTool: Bool = false
    ) -> FinishReason {
        switch raw {
        case "stop_sequence", "end_turn":
            .stop
        case "max_tokens":
            .length
        case "content_filtered", "guardrail_intervened":
            .contentFilter
        case "tool_use":
            isJsonResponseFromTool ? .stop : .toolCalls
        default:
            .other
        }
    }
}
