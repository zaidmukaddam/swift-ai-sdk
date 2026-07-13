import Foundation

public typealias MiddlewareNext =
    @Sendable (LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error>

public struct MiddlewareCallContext: Sendable {
    public var request: LanguageModelRequest
    public var provider: String
    public var modelID: String
}

public struct LanguageModelMiddleware: Sendable {
    public var transformRequest: (@Sendable (LanguageModelRequest) async throws -> LanguageModelRequest)?

    public var wrapCall: (@Sendable (MiddlewareCallContext, MiddlewareNext) async throws -> AsyncThrowingStream<StreamPart, Error>)?

    public var wrapStream: (@Sendable (AsyncThrowingStream<StreamPart, Error>) -> AsyncThrowingStream<StreamPart, Error>)?

    public init(
        transformRequest: (@Sendable (LanguageModelRequest) async throws -> LanguageModelRequest)? = nil,
        wrapCall: (@Sendable (MiddlewareCallContext, MiddlewareNext) async throws -> AsyncThrowingStream<StreamPart, Error>)? = nil,
        wrapStream: (@Sendable (AsyncThrowingStream<StreamPart, Error>) -> AsyncThrowingStream<StreamPart, Error>)? = nil
    ) {
        self.transformRequest = transformRequest
        self.wrapCall = wrapCall
        self.wrapStream = wrapStream
    }
}

public struct WrappedLanguageModel: LanguageModel {
    public let base: any LanguageModel
    public let middleware: [LanguageModelMiddleware]

    public var provider: String { base.provider }
    public var modelID: String { base.modelID }

    public init(base: any LanguageModel, middleware: [LanguageModelMiddleware]) {
        self.base = base
        self.middleware = middleware
    }

    public func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        var transformed = request
        for entry in middleware {
            if let transform = entry.transformRequest {
                transformed = try await transform(transformed)
            }
        }

        let base = self.base
        var next: MiddlewareNext = { req in try await base.stream(req) }
        for entry in middleware.reversed() {
            guard let wrapCall = entry.wrapCall else { continue }
            let inner = next
            next = { req in
                try await wrapCall(
                    MiddlewareCallContext(request: req, provider: base.provider, modelID: base.modelID),
                    inner
                )
            }
        }

        var stream = try await next(transformed)
        for entry in middleware.reversed() {
            if let wrap = entry.wrapStream {
                stream = wrap(stream)
            }
        }
        return stream
    }
}

public func wrapLanguageModel(
    model: any LanguageModel,
    middleware: [LanguageModelMiddleware]
) -> any LanguageModel {
    WrappedLanguageModel(base: model, middleware: middleware)
}

private let libraryDefaultMaxOutputTokens = 1024

public extension LanguageModelMiddleware {

    static func extractReasoning(tag: String = "think") -> LanguageModelMiddleware {
        let openingTag = "<\(tag)>"
        let closingTag = "</\(tag)>"

        return LanguageModelMiddleware(wrapStream: { inner in
            AsyncThrowingStream { continuation in
                let task = Task {
                    var buffer = ""
                    var isReasoning = false

                    func publish(_ text: String) {
                        guard !text.isEmpty else { return }
                        continuation.yield(isReasoning ? .reasoningDelta(text) : .textDelta(text))
                    }

                    func flush() {
                        publish(buffer)
                        buffer = ""
                    }

                    func scan() {
                        while true {
                            let nextTag = isReasoning ? closingTag : openingTag
                            guard let start = potentialTagStart(of: nextTag, in: buffer) else {
                                flush()
                                return
                            }
                            publish(String(buffer.prefix(start)))
                            let remainder = String(buffer.dropFirst(start))
                            if remainder.hasPrefix(nextTag) {
                                buffer = String(remainder.dropFirst(nextTag.count))
                                isReasoning.toggle()
                            } else {
                                buffer = remainder
                                return
                            }
                        }
                    }

                    do {
                        for try await part in inner {
                            switch part {
                            case .textDelta(let delta):
                                buffer += delta
                                scan()
                            case .finish:
                                flush()
                                continuation.yield(part)
                            default:
                                continuation.yield(part)
                            }
                        }
                        flush()
                        continuation.finish()
                    } catch {
                        flush()
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
    }

    static func simulateStreaming() -> LanguageModelMiddleware {
        LanguageModelMiddleware(wrapStream: { inner in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var parts: [StreamPart] = []
                        for try await part in inner { parts.append(part) }
                        for part in coalescingAdjacentDeltas(parts) {
                            continuation.yield(part)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
    }

    static func cache(
        store: any LanguageModelCache = InMemoryLanguageModelCache()
    ) -> LanguageModelMiddleware {
        LanguageModelMiddleware(wrapCall: { context, next in
            let key = cacheKey(context)
            if let cached = await store.get(key) {
                return AsyncThrowingStream { continuation in
                    for part in cached { continuation.yield(part) }
                    continuation.finish()
                }
            }
            let live = try await next(context.request)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var parts: [StreamPart] = []
                        for try await part in live {
                            parts.append(part)
                            continuation.yield(part)
                        }
                        await store.set(key, parts)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
    }

    static func defaultSettings(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        providerOptions: JSONValue? = nil
    ) -> LanguageModelMiddleware {
        LanguageModelMiddleware(transformRequest: { request in
            var request = request
            if request.temperature == nil, let temperature {
                request.temperature = temperature
            }
            if request.topP == nil, let topP {
                request.topP = topP
            }
            if request.maxOutputTokens == libraryDefaultMaxOutputTokens, let maxOutputTokens {
                request.maxOutputTokens = maxOutputTokens
            }
            if let providerOptions {
                request.providerOptions = deepMergeJSON(
                    defaults: providerOptions, overrides: request.providerOptions
                )
            }
            return request
        })
    }
}

public protocol LanguageModelCache: Sendable {
    func get(_ key: String) async -> [StreamPart]?
    func set(_ key: String, _ value: [StreamPart]) async
}

public actor InMemoryLanguageModelCache: LanguageModelCache {
    private var storage: [String: [StreamPart]] = [:]

    public init() {}

    public func get(_ key: String) -> [StreamPart]? { storage[key] }
    public func set(_ key: String, _ value: [StreamPart]) { storage[key] = value }

    public func removeAll() { storage.removeAll() }
}

func cacheKey(_ context: MiddlewareCallContext) -> String {
    let request = context.request
    var object: [String: JSONValue] = [
        "provider": .string(context.provider),
        "model": .string(context.modelID),
        "messages": .array(request.messages.map(messageCacheJSON)),
        "maxOutputTokens": .number(Double(request.maxOutputTokens)),
        "reasoning": .string(request.reasoning.rawValue),
        "toolChoice": toolChoiceCacheJSON(request.toolChoice),
        "responseFormat": responseFormatCacheJSON(request.responseFormat)
    ]
    if !request.tools.isEmpty {
        object["tools"] = .array(request.tools.map {
            .object([
                "name": .string($0.name),
                "description": .string($0.description),
                "parameters": $0.parameters
            ])
        })
    }
    if let value = request.temperature { object["temperature"] = .number(value) }
    if let value = request.topP { object["topP"] = .number(value) }
    if let value = request.topK { object["topK"] = .number(Double(value)) }
    if let value = request.presencePenalty { object["presencePenalty"] = .number(value) }
    if let value = request.frequencyPenalty { object["frequencyPenalty"] = .number(value) }
    if let value = request.seed { object["seed"] = .number(Double(value)) }
    if !request.stopSequences.isEmpty {
        object["stopSequences"] = .array(request.stopSequences.map { .string($0) })
    }
    if let value = request.providerOptions { object["providerOptions"] = value }

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = (try? encoder.encode(JSONValue.object(object))) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

private func messageCacheJSON(_ message: Message) -> JSONValue {
    .object([
        "role": .string(message.role.rawValue),
        "content": .array(message.content.map(contentPartCacheJSON))
    ])
}

private func contentPartCacheJSON(_ part: ContentPart) -> JSONValue {
    switch part {
    case .text(let text):
        return .object(["kind": "text", "text": .string(text)])
    case .image(let image):
        return .object([
            "kind": "image",
            "mediaType": .string(image.resolvedMediaType),
            "source": .string(image.url?.absoluteString ?? image.data?.base64EncodedString() ?? "")
        ])
    case .file(let file):
        return .object([
            "kind": "file",
            "mediaType": .string(file.mediaType),
            "filename": .string(file.filename ?? ""),
            "source": .string(file.url?.absoluteString ?? file.data?.base64EncodedString() ?? "")
        ])
    case .toolCall(let call):
        return .object([
            "kind": "toolCall",
            "id": .string(call.id),
            "name": .string(call.name),
            "arguments": call.arguments,
            "providerExecuted": .bool(call.providerExecuted)
        ])
    case .toolResult(let result):
        return .object([
            "kind": "toolResult",
            "id": .string(result.toolCallID),
            "name": .string(result.name),
            "output": result.output,
            "isError": .bool(result.isError),
            "denied": .bool(result.denied)
        ])
    case .toolApprovalResponse(let response):
        return .object([
            "kind": "approval",
            "id": .string(response.approvalID),
            "toolCallID": .string(response.toolCallID),
            "approved": .bool(response.approved)
        ])
    }
}

private func toolChoiceCacheJSON(_ choice: ToolChoice) -> JSONValue {
    switch choice {
    case .auto: return .string("auto")
    case .none: return .string("none")
    case .required: return .string("required")
    case .tool(let name): return .object(["tool": .string(name)])
    }
}

private func responseFormatCacheJSON(_ format: ResponseFormat) -> JSONValue {
    switch format {
    case .text: return .string("text")
    case .jsonNoSchema: return .string("jsonNoSchema")
    case .json(let schema, let name, let description):
        return .object([
            "type": "json",
            "name": .string(name),
            "schema": schema,
            "description": .string(description ?? "")
        ])
    }
}

private func potentialTagStart(of tag: String, in text: String) -> Int? {
    guard !tag.isEmpty else { return nil }
    if let range = text.range(of: tag) {
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
    let maxOverlap = min(text.count, tag.count - 1)
    guard maxOverlap >= 1 else { return nil }
    for length in 1...maxOverlap where tag.hasPrefix(text.suffix(length)) {
        return text.count - length
    }
    return nil
}

private func coalescingAdjacentDeltas(_ parts: [StreamPart]) -> [StreamPart] {
    var out: [StreamPart] = []
    for part in parts {
        switch (out.last, part) {
        case (.textDelta(let a), .textDelta(let b)):
            out[out.count - 1] = .textDelta(a + b)
        case (.reasoningDelta(let a), .reasoningDelta(let b)):
            out[out.count - 1] = .reasoningDelta(a + b)
        default:
            out.append(part)
        }
    }
    return out
}

private func deepMergeJSON(defaults: JSONValue, overrides: JSONValue?) -> JSONValue {
    guard let overrides else { return defaults }
    guard case .object(let base) = defaults, case .object(let over) = overrides else {
        return overrides
    }
    var merged = base
    for (key, value) in over {
        if let existing = merged[key] {
            merged[key] = deepMergeJSON(defaults: existing, overrides: value)
        } else {
            merged[key] = value
        }
    }
    return .object(merged)
}
