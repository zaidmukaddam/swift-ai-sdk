#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct FoundationModelsModel: LanguageModel {
    public let provider = "apple"
    public let modelID: String

    private let makeSession: @Sendable ([any FoundationModels.Tool], Transcript) -> LanguageModelSession

    public init(systemModel: SystemLanguageModel = .default) {
        self.modelID = "foundation-models"
        self.makeSession = { tools, transcript in
            LanguageModelSession(model: systemModel, tools: tools, transcript: transcript)
        }
    }

    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    public static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    public static func orFallback(_ fallback: any LanguageModel) -> any LanguageModel {
        isAvailable ? FoundationModelsModel() : fallback
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let tools = request.tools.map { BridgedTool(inner: $0) as any FoundationModels.Tool }
        let (transcript, prompt) = Self.transcriptAndPrompt(from: request.messages)

        let session = makeSession(tools, transcript)

        var options = GenerationOptions()
        options.temperature = request.temperature
        options.maximumResponseTokens = request.maxOutputTokens

        if case .json(let schema, let name, _) = request.responseFormat {
            let generationSchema = try JSONSchemaConversion.generationSchema(from: schema, name: name)
            return Self.streamGuided(
                session: session, prompt: prompt, schema: generationSchema, options: options
            )
        }

        return Self.streamText(session: session, prompt: prompt, options: options)
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    public init(privateCloudCompute model: PrivateCloudComputeLanguageModel) {
        self.modelID = "foundation-models-pcc"
        self.makeSession = { tools, transcript in
            LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    public static func privateCloudCompute() -> FoundationModelsModel {
        FoundationModelsModel(privateCloudCompute: PrivateCloudComputeLanguageModel())
    }
    #endif

    private static func streamText(
        session: LanguageModelSession,
        prompt: String,
        options: GenerationOptions
    ) -> AsyncThrowingStream<StreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var emitted = ""
                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        let content = snapshot.content
                        if content.hasPrefix(emitted) {
                            let delta = String(content.dropFirst(emitted.count))
                            if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                        } else {
                            continuation.yield(.textDelta(content))
                        }
                        emitted = content
                    }
                    continuation.yield(.finish(reason: .stop, usage: Usage()))
                    continuation.finish()
                } catch where Self.isContentFiltered(error) {
                    continuation.yield(.finish(reason: .contentFilter, usage: Usage()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func streamGuided(
        session: LanguageModelSession,
        prompt: String,
        schema: GenerationSchema,
        options: GenerationOptions
    ) -> AsyncThrowingStream<StreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var emitted = ""
                    for try await snapshot in session.streamResponse(
                        to: prompt, schema: schema, options: options
                    ) {
                        let json = snapshot.content.jsonString
                        if json.hasPrefix(emitted) {
                            let delta = String(json.dropFirst(emitted.count))
                            if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                        } else {
                            continuation.yield(.textDelta(json))
                        }
                        emitted = json
                    }
                    continuation.yield(.finish(reason: .stop, usage: Usage()))
                    continuation.finish()
                } catch where Self.isContentFiltered(error) {
                    continuation.yield(.finish(reason: .contentFilter, usage: Usage()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func transcriptAndPrompt(from messages: [Message]) -> (Transcript, String) {
        var turns = messages.filter { $0.role != .system }
        var prompt = ""
        if turns.last?.role == .user {
            prompt = turns.removeLast().text
        }

        var entries: [Transcript.Entry] = []
        let system = messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        if !system.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: system))],
                toolDefinitions: []
            )))
        }
        for message in turns {
            let text = message.text
            guard !text.isEmpty else { continue }
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            case .assistant:
                entries.append(.response(Transcript.Response(
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            case .tool, .system:
                continue
            }
        }
        return (Transcript(entries: entries), prompt)
    }

    static func mapError(_ error: Error) -> Error {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            #if compiler(>=6.4)
            if let pccError = error as? PrivateCloudComputeLanguageModel.Error {
                if case .quotaLimitReached = pccError {
                    return AIError.transport(
                        "Private Cloud Compute daily quota reached. It refreshes "
                        + "daily, or the user can upgrade via iCloud+. (\(pccError))"
                    )
                }
                return AIError.transport("Private Cloud Compute: \(pccError)")
            }
            #endif
            if let systemError = error as? SystemLanguageModel.Error {
                switch systemError {
                case .assetsUnavailable:
                    return AIError.transport(
                        "Foundation Models assets are unavailable. Apple Intelligence "
                        + "may still be downloading its models. Check System Settings "
                        + "> Apple Intelligence, then retry. (\(systemError))"
                    )
                @unknown default:
                    return AIError.transport("Foundation Models: \(systemError)")
                }
            }
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .contextSizeExceeded:
                    return AIError.invalidRequest(
                        "Foundation Models context window exceeded: \(modelError)"
                    )
                case .rateLimited:
                    return AIError.http(status: 429, body: "Foundation Models rate limited")
                default:
                    return AIError.transport("Foundation Models: \(modelError)")
                }
            }
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            return AIError.transport("Foundation Models: \(generationError)")
        }
        let nsError = error as NSError
        if nsError.domain.hasPrefix("FoundationModels") {
            if "\(nsError)".contains("ModelManagerError") {
                return AIError.transport(
                    "Foundation Models could not load a required model asset. "
                    + "Apple Intelligence may still be downloading. Check System "
                    + "Settings > Apple Intelligence & Siri, then retry. (\(nsError.domain))"
                )
            }
            return AIError.transport("Foundation Models: \(error)")
        }
        return error
    }

    static func isContentFiltered(_ error: Error) -> Bool {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .guardrailViolation, .refusal: return true
                default: return false
                }
            }
        }
        return false
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct BridgedTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let inner: any AIToolProtocol

    var name: String { inner.name }
    var description: String { inner.description }

    var parameters: GenerationSchema {
        (try? JSONSchemaConversion.generationSchema(from: inner.parameters, name: inner.name))
            ?? GenerationSchema(
                type: GeneratedContent.self,
                description: inner.description,
                properties: []
            )
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let json = arguments.jsonString
        let value = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .object([:])
        let output = try await inner.execute(value)
        if case .string(let s) = output { return s }
        let data = try JSONEncoder().encode(output)
        return String(decoding: data, as: UTF8.self)
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
enum JSONSchemaConversion {
    static func generationSchema(from schema: JSONValue, name: String) throws -> GenerationSchema {
        let root = try dynamicSchema(from: schema, name: name)
        return try GenerationSchema(root: root, dependencies: [])
    }

    static func dynamicSchema(from schema: JSONValue, name: String) throws -> DynamicGenerationSchema {
        let description = schema["description"]?.stringValue

        if let choices = schema["enum"]?.arrayValue {
            let strings = choices.compactMap(\.stringValue)
            if !strings.isEmpty {
                return DynamicGenerationSchema(name: name, description: description, anyOf: strings)
            }
        }

        switch schema["type"]?.stringValue {
        case "object":
            let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            var properties: [DynamicGenerationSchema.Property] = []
            if let props = schema["properties"]?.objectValue {
                for key in props.keys.sorted() {
                    let propSchema = try dynamicSchema(from: props[key]!, name: key)
                    properties.append(DynamicGenerationSchema.Property(
                        name: key,
                        description: props[key]!["description"]?.stringValue,
                        schema: propSchema,
                        isOptional: !required.contains(key)
                    ))
                }
            }
            return DynamicGenerationSchema(name: name, description: description, properties: properties)

        case "array":
            let itemSchema = try dynamicSchema(
                from: schema["items"] ?? .object([:]), name: "\(name)Item"
            )
            return DynamicGenerationSchema(
                arrayOf: itemSchema,
                minimumElements: schema["minItems"]?.intValue,
                maximumElements: schema["maxItems"]?.intValue
            )

        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        default:
            throw AIError.invalidRequest(
                "Unsupported JSON Schema for guided generation: \(schema)"
            )
        }
    }
}
#endif
