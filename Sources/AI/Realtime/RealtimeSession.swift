import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RealtimeConversationReducer {
    enum Effect {
        case playAudio(itemID: String, base64Audio: String)
        case speechStarted
        case toolCall(ToolCall)
        case error(String)
    }

    private(set) var messages: [UIMessage] = []
    private(set) var events: [RealtimeServerEvent] = []
    private let maxEvents: Int

    private var currentAssistantMessageID: String?
    private var textAccumulators: [String: String] = [:]
    private var toolCallIDToMessageID: [String: String] = [:]
    private var toolCallIDToName: [String: String] = [:]
    private var inputAudioMessageInsertIndex: [String: Int] = [:]
    private var itemIDToPartLocation: [String: (messageID: String, partIndex: Int)] = [:]

    init(maxEvents: Int = 500) {
        self.maxEvents = maxEvents
    }

    func addUserTextMessage(_ text: String) {
        messages.append(UIMessage(
            id: "user-\(UUID().uuidString)", role: .user,
            parts: [.text(TextUIPart(text: text, state: .done))]
        ))
    }

    func addToolOutput(callID: String, output: JSONValue) -> (name: String?, outputJSON: String) {
        if let messageID = toolCallIDToMessageID[callID] {
            updateToolPart(messageID: messageID, callID: callID) { part in
                part.state = .outputAvailable
                part.output = output
            }
        }
        let data = (try? JSONEncoder().encode(output)) ?? Data("null".utf8)
        return (toolCallIDToName[callID], String(decoding: data, as: UTF8.self))
    }

    func reduce(_ event: RealtimeServerEvent) -> [Effect] {
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }

        switch event {
        case .audioDelta(_, let itemID, let delta, _):
            return [.playAudio(itemID: itemID, base64Audio: delta)]

        case .audioCommitted(let itemID, _, _):
            if let itemID { inputAudioMessageInsertIndex[itemID] = messages.count }
            return []

        case .audioTranscriptDelta(_, let itemID, let delta, _),
             .textDelta(_, let itemID, let delta, _):
            appendTextDelta(itemID: itemID, delta: delta)
            return []

        case .audioTranscriptDone(_, let itemID, let transcript, _):
            finalizeText(itemID: itemID, finalText: transcript)
            return []

        case .textDone(_, let itemID, let text, _):
            finalizeText(itemID: itemID, finalText: text)
            return []

        case .inputTranscriptionCompleted(let itemID, let transcript, _):
            addInputTranscriptionMessage(itemID: itemID, transcript: transcript)
            return []

        case .responseCreated, .responseDone:
            currentAssistantMessageID = nil
            return []

        case .speechStarted:
            currentAssistantMessageID = nil
            return [.speechStarted]

        case .functionCallArgumentsDelta(_, _, let callID, _, _):
            let messageID = getOrCreateAssistantMessage()
            toolCallIDToMessageID[callID] = messageID
            ensureToolPart(messageID: messageID, callID: callID)
            return []

        case .functionCallArgumentsDone(_, _, let callID, let name, let arguments, _):
            toolCallIDToName[callID] = name
            guard let input = try? JSONDecoder().decode(
                JSONValue.self, from: Data(arguments.utf8)
            ) else {
                return [.error("Failed to parse tool arguments: \(arguments)")]
            }
            let messageID = toolCallIDToMessageID[callID] ?? getOrCreateAssistantMessage()
            toolCallIDToMessageID[callID] = messageID
            ensureToolPart(messageID: messageID, callID: callID)
            updateToolPart(messageID: messageID, callID: callID) { part in
                part.toolName = name
                part.state = .inputAvailable
                part.input = input
            }
            return [.toolCall(ToolCall(id: callID, name: name, arguments: input))]

        case .error(let message, _, _):
            return [.error(message)]

        default:
            return []
        }
    }

    private func getOrCreateAssistantMessage() -> String {
        if let id = currentAssistantMessageID { return id }
        let id = "assistant-\(UUID().uuidString)"
        currentAssistantMessageID = id
        messages.append(UIMessage(id: id, role: .assistant, parts: []))
        return id
    }

    private func appendTextDelta(itemID: String, delta: String) {
        let messageID = getOrCreateAssistantMessage()
        let text = (textAccumulators[itemID] ?? "") + delta
        textAccumulators[itemID] = text

        if let location = itemIDToPartLocation[itemID] {
            updatePart(
                messageID: location.messageID, partIndex: location.partIndex,
                part: .text(TextUIPart(text: text, state: .streaming))
            )
            return
        }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        itemIDToPartLocation[itemID] = (messageID, messages[index].parts.count)
        messages[index].parts.append(.text(TextUIPart(text: text, state: .streaming)))
    }

    private func finalizeText(itemID: String, finalText: String?) {
        let text = finalText ?? textAccumulators[itemID] ?? ""
        textAccumulators[itemID] = nil
        guard let location = itemIDToPartLocation[itemID] else { return }
        itemIDToPartLocation[itemID] = nil
        updatePart(
            messageID: location.messageID, partIndex: location.partIndex,
            part: .text(TextUIPart(text: text, state: .done))
        )
    }

    private func addInputTranscriptionMessage(itemID: String, transcript: String) {
        let messageID = "user-\(itemID)"
        let part = UIPart.text(TextUIPart(text: transcript, state: .done))
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].parts = [part]
            return
        }
        let insertIndex = min(
            inputAudioMessageInsertIndex[itemID] ?? messages.count, messages.count
        )
        messages.insert(
            UIMessage(id: messageID, role: .user, parts: [part]), at: insertIndex
        )
    }

    private func ensureToolPart(messageID: String, callID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let exists = messages[index].parts.contains {
            if case .tool(let tool) = $0 { return tool.toolCallID == callID }
            return false
        }
        guard !exists else { return }
        messages[index].parts.append(.tool(ToolUIPart(
            toolName: "", toolCallID: callID, state: .inputStreaming, isDynamic: true
        )))
    }

    private func updateToolPart(
        messageID: String, callID: String, mutate: (inout ToolUIPart) -> Void
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].parts = messages[index].parts.map { part in
            guard case .tool(var tool) = part, tool.toolCallID == callID else { return part }
            mutate(&tool)
            return .tool(tool)
        }
    }

    private func updatePart(messageID: String, partIndex: Int, part: UIPart) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].parts.indices.contains(partIndex) else { return }
        messages[index].parts[partIndex] = part
    }
}

final class RealtimeTransport: @unchecked Sendable {
    private let model: any RealtimeModel
    private let urlSession: URLSession
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?

    init(model: any RealtimeModel, urlSession: URLSession = .shared) {
        self.model = model
        self.urlSession = urlSession
    }

    func connect(
        secret: RealtimeClientSecret,
        onOpen: @escaping @Sendable () -> Void,
        onServerEvent: @escaping @Sendable (RealtimeServerEvent) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) {
        disconnect()
        let config = model.webSocketConfig(token: secret.token, url: secret.url)
        let socket = config.protocols.isEmpty
            ? urlSession.webSocketTask(with: config.url)
            : urlSession.webSocketTask(with: config.url, protocols: config.protocols)
        lock.lock()
        task = socket
        lock.unlock()
        socket.resume()
        onOpen()

        let model = self.model
        let loop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    let text: String
                    switch message {
                    case .string(let string): text = string
                    case .data(let data): text = String(decoding: data, as: UTF8.self)
                    @unknown default: continue
                    }
                    guard let raw = try? JSONDecoder().decode(
                        JSONValue.self, from: Data(text.utf8)
                    ) else { continue }
                    if let response = model.healthCheckResponse(for: raw) {
                        self?.sendRaw(response)
                    }
                    for event in model.parseServerEvent(raw) {
                        onServerEvent(event)
                    }
                } catch {
                    if !Task.isCancelled { onError(error) }
                    onClose()
                    return
                }
            }
        }
        lock.lock()
        receiveLoop = loop
        lock.unlock()
    }

    func send(_ event: RealtimeClientEvent) {
        guard let payload = model.serializeClientEvent(event) else { return }
        sendRaw(payload)
    }

    func sendRaw(_ payload: JSONValue) {
        lock.lock()
        let socket = task
        lock.unlock()
        guard let socket, let data = try? JSONEncoder().encode(payload) else { return }
        socket.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    func disconnect() {
        lock.lock()
        let socket = task
        let loop = receiveLoop
        task = nil
        receiveLoop = nil
        lock.unlock()
        loop?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
    }
}

#if canImport(Observation)
import Observation

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable @MainActor
public final class RealtimeSession {
    public enum Status: String, Sendable {
        case disconnected, connecting, connected, error
    }

    public private(set) var status: Status = .disconnected
    public private(set) var messages: [UIMessage] = []
    public private(set) var events: [RealtimeServerEvent] = []

    public var onToolCall: (@Sendable (ToolCall) async throws -> JSONValue?)?
    public var onEvent: ((RealtimeServerEvent) -> Void)?
    public var onError: ((Error) -> Void)?

    public let audioOutput: AsyncStream<Data>

    private let model: any RealtimeModel
    private var sessionConfig: RealtimeSessionConfig
    private let transport: RealtimeTransport
    private let reducer: RealtimeConversationReducer
    private let audioContinuation: AsyncStream<Data>.Continuation

    private var currentResponseItemID: String?
    private var toolCallsInResponse: Set<String> = []
    private var submittedToolOutputs: Set<String> = []
    private var responseToolCallsClosed = false

    public init(
        model: any RealtimeModel,
        sessionConfig: RealtimeSessionConfig = RealtimeSessionConfig(),
        maxEvents: Int = 500,
        urlSession: URLSession = .shared,
        onToolCall: (@Sendable (ToolCall) async throws -> JSONValue?)? = nil
    ) {
        self.model = model
        self.sessionConfig = sessionConfig
        self.transport = RealtimeTransport(model: model, urlSession: urlSession)
        self.reducer = RealtimeConversationReducer(maxEvents: maxEvents)
        self.onToolCall = onToolCall
        (self.audioOutput, self.audioContinuation) = AsyncStream.makeStream(of: Data.self)
    }

    public func connect(secret: RealtimeClientSecret) {
        status = .connecting
        let config = sessionConfig
        transport.connect(
            secret: secret,
            onOpen: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.send(event: .sessionUpdate(config))
                }
            },
            onServerEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleServerEvent(event)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.status = .error
                    self?.onError?(error)
                }
            },
            onClose: { [weak self] in
                Task { @MainActor [weak self] in
                    if self?.status != .error { self?.status = .disconnected }
                }
            }
        )
    }

    public func connect(
        tokenEndpoint: URL, urlSession: URLSession = .shared
    ) async throws {
        status = .connecting
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let configPayload = model.buildSessionConfig(sessionConfig)
        request.httpBody = try JSONEncoder().encode(
            JSONValue.object(["sessionConfig": configPayload])
        )
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            status = .error
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let token = decoded["token"]?.stringValue,
              let url = decoded["url"]?.stringValue else {
            status = .error
            throw AIError.decoding("Realtime setup endpoint returned no token/url")
        }
        if let tools = decoded["tools"]?.arrayValue {
            sessionConfig.tools = tools.compactMap { wire in
                guard let name = wire["name"]?.stringValue else { return nil }
                return RealtimeToolDefinition(
                    name: name,
                    description: wire["description"]?.stringValue,
                    parameters: wire["parameters"] ?? .object([:])
                )
            }
        }
        connect(secret: RealtimeClientSecret(
            token: token, url: url, expiresAt: decoded["expiresAt"]?.intValue
        ))
    }

    public func disconnect() {
        transport.disconnect()
        status = .disconnected
    }

    public func sendText(_ text: String) {
        send(event: .conversationItemCreate(.textMessage(text)))
        send(event: .responseCreate())
        reducer.addUserTextMessage(text)
        messages = reducer.messages
    }

    public func sendAudio(_ audio: Data) {
        send(event: .inputAudioAppend(base64Audio: audio.base64EncodedString()))
    }

    public func commitAudio() {
        send(event: .inputAudioCommit)
    }

    public func clearAudioBuffer() {
        send(event: .inputAudioClear)
    }

    public func requestResponse(modalities: [String]? = nil) {
        send(event: .responseCreate(modalities: modalities))
    }

    public func cancelResponse() {
        send(event: .responseCancel)
    }

    public func send(event: RealtimeClientEvent) {
        transport.send(event)
    }

    public func playbackInterrupted(playedMilliseconds: Int) {
        guard let itemID = currentResponseItemID else { return }
        send(event: .conversationItemTruncate(
            itemID: itemID, contentIndex: 0, audioEndMs: playedMilliseconds
        ))
    }

    public func addToolOutput(callID: String, output: JSONValue) {
        let (name, outputJSON) = reducer.addToolOutput(callID: callID, output: output)
        messages = reducer.messages
        send(event: .conversationItemCreate(.functionCallOutput(
            callID: callID, name: name, output: outputJSON
        )))
        submittedToolOutputs.insert(callID)
        maybeRequestToolResponse()
    }

    private func handleServerEvent(_ event: RealtimeServerEvent) {
        if case .sessionCreated = event, status == .connecting { status = .connected }
        if case .sessionUpdated = event, status == .connecting { status = .connected }

        let effects = reducer.reduce(event)
        messages = reducer.messages
        events = reducer.events
        onEvent?(event)

        for effect in effects {
            switch effect {
            case .playAudio(let itemID, let base64Audio):
                currentResponseItemID = itemID
                if let data = Data(base64Encoded: base64Audio) {
                    audioContinuation.yield(data)
                }
            case .speechStarted:
                break
            case .toolCall(let call):
                toolCallsInResponse.insert(call.id)
                executeToolCall(call)
            case .error(let message):
                onError?(AIError.invalidRequest(message))
            }
        }

        if case .responseDone = event, !toolCallsInResponse.isEmpty {
            responseToolCallsClosed = true
            maybeRequestToolResponse()
        }
    }

    private func executeToolCall(_ call: ToolCall) {
        guard let handler = onToolCall else {
            onError?(AIError.unknownTool(call.name))
            return
        }
        Task { @MainActor [weak self] in
            do {
                if let output = try await handler(call) {
                    self?.addToolOutput(callID: call.id, output: output)
                }
            } catch {
                self?.onError?(error)
            }
        }
    }

    private func maybeRequestToolResponse() {
        guard responseToolCallsClosed, !toolCallsInResponse.isEmpty else { return }
        guard toolCallsInResponse.allSatisfy(submittedToolOutputs.contains) else { return }
        send(event: .responseCreate())
        toolCallsInResponse.removeAll()
        submittedToolOutputs.removeAll()
        responseToolCallsClosed = false
    }
}
#endif
