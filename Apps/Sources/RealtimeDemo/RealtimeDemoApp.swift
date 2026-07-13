import AI
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct RealtimeDemoApp: App {
    init() {
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RealtimeView()
        }
    }
}

@Observable @MainActor
final class RealtimeViewModel {
    enum Provider: String, CaseIterable, Identifiable {
        case xai = "xAI grok-voice-latest"
        case openai = "OpenAI gpt-realtime"
        case google = "Google gemini-live"

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .xai: return "xAI"
            case .openai: return "OpenAI"
            case .google: return "Gemini"
            }
        }

        var keyName: String {
            switch self {
            case .xai: return "XAI_API_KEY"
            case .openai: return "OPENAI_API_KEY"
            case .google: return "GOOGLE_GENERATIVE_AI_API_KEY"
            }
        }
    }

    var provider: Provider = .xai
    var apiKey: String = ""
    var session: RealtimeSession?
    var statusLine = "disconnected"
    var eventLog: [String] = []
    var lastToolCall = ""
    var lastError = ""
    var micOn = false
    var bytesPlayed = 0

    private let player = AudioPlayer()
    private let mic = MicCapture()
    private var audioPump: Task<Void, Never>?

    var isConnected: Bool { statusLine == "connected" }
    var isBusy: Bool { statusLine == "connecting" || statusLine == "minting client secret" }

    func resolvedKey() -> String {
        let typed = apiKey.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        return ProcessInfo.processInfo.environment[provider.keyName] ?? ""
    }

    private func makeModel(key: String) -> any RealtimeModel {
        switch provider {
        case .xai: return XaiRealtimeModel("grok-voice-latest", apiKey: key)
        case .openai: return OpenAIRealtimeModel("gpt-realtime", apiKey: key)
        case .google: return GoogleRealtimeModel("gemini-2.5-flash-native-audio-preview-09-2025", apiKey: key)
        }
    }

    private var timeTool: Tool {
        Tool(
            name: "getTime",
            description: "Get the current local time.",
            parameters: .object(["type": .string("object"), "properties": .object([:])])
        ) { _ in .null }
    }

    func connect() async {
        let key = resolvedKey()
        guard !key.isEmpty else {
            lastError = "No API key: set \(provider.keyName) or add one in settings"
            return
        }
        lastError = ""
        statusLine = "minting client secret"
        let model = makeModel(key: key)

        let config = RealtimeSessionConfig(
            instructions: "You are a friendly, very concise voice assistant.",
            inputAudioTranscription: .init(),
            tools: getRealtimeToolDefinitions(tools: [timeTool])
        )
        let session = RealtimeSession(
            model: model,
            sessionConfig: config,
            onToolCall: { call in
                if call.name == "getTime" {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    return .object(["time": .string(formatter.string(from: Date()))])
                }
                return nil
            }
        )
        session.onEvent = { [weak self] event in
            self?.log(event)
        }
        session.onError = { [weak self] error in
            self?.lastError = "\(error)"
            print("realtime error: \(error)")
        }
        self.session = session

        audioPump?.cancel()
        audioPump = Task { [weak self] in
            guard let stream = self?.session?.audioOutput else { return }
            for await chunk in stream {
                guard let self else { return }
                self.player.play(chunk)
                self.bytesPlayed = self.player.bytesPlayed
            }
        }

        do {
            statusLine = "connecting"
            let secret = try await model.createClientSecret(
                options: RealtimeClientSecretOptions(
                    expiresAfterSeconds: 600,
                    sessionConfig: config
                )
            )
            session.connect(secret: secret)
        } catch {
            lastError = "client secret: \(error)"
            statusLine = "error"
            print("client secret error: \(error)")
        }
    }

    func disconnect() {
        mic.stop()
        micOn = false
        audioPump?.cancel()
        session?.disconnect()
        player.stop()
        statusLine = "disconnected"
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.sendText(trimmed)
    }

    func toggleMic() {
        if micOn {
            mic.stop()
            micOn = false
            return
        }
        do {
            try mic.start { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.session?.sendAudio(chunk)
                }
            }
            micOn = true
        } catch {
            lastError = "microphone: \(error.localizedDescription)"
        }
    }

    private func log(_ event: RealtimeServerEvent) {
        let name: String
        switch event {
        case .sessionCreated: name = "session-created"
        case .sessionUpdated: name = "session-updated"
        case .speechStarted:
            name = "speech-started"
            let played = player.playedMilliseconds
            player.stop()
            session?.playbackInterrupted(playedMilliseconds: played)
        case .speechStopped: name = "speech-stopped"
        case .audioDelta: name = "audio-delta"
        case .audioTranscriptDelta: name = "transcript-delta"
        case .textDelta: name = "text-delta"
        case .responseDone: name = "response-done"
        case .inputTranscriptionCompleted: name = "input-transcription"
        case .functionCallArgumentsDone(_, _, _, let toolName, _, _):
            name = "tool-call \(toolName)"
            lastToolCall = toolName
        case .error(let message, _, _): name = "error: \(message)"
        case .custom(let rawType, _): name = rawType
        default: name = "\(event)".components(separatedBy: "(").first ?? "event"
        }
        if eventLog.last != name {
            eventLog.append(name)
            if eventLog.count > 12 { eventLog.removeFirst(eventLog.count - 12) }
        }
        if case .sessionCreated = event { statusLine = "connected" }
        if case .sessionUpdated = event { statusLine = "connected" }
    }
}

struct RealtimeView: View {
    @State private var model = RealtimeViewModel()
    @State private var input = ""
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if model.session?.messages.isEmpty != false {
                    EmptyVoiceView(
                        isConnected: model.isConnected,
                        providerLabel: model.provider.shortLabel
                    )
                } else {
                    conversation
                }
            }
            .navigationTitle("Voice")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem {
                    StatusPill(status: model.statusLine)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(model: model)
            }
        }
        .tint(.primary)
        .sensoryFeedback(.success, trigger: model.statusLine) { _, newValue in
            newValue == "connected"
        }
        .task { await runSmokeIfRequested() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.session?.messages ?? []) { message in
                        RealtimeMessageView(message: message)
                            .id(message.id)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .move(edge: .bottom))
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(
                    reduceMotion ? nil : .spring(duration: 0.35, bounce: 0),
                    value: model.session?.messages.count ?? 0
                )
            }
            .onChange(of: model.session?.messages.count ?? 0) {
                guard let lastUser = model.session?.messages.last(where: { $0.role == .user })
                else { return }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0)) {
                    proxy.scrollTo(lastUser.id, anchor: .top)
                }
            }
            .onChange(of: model.session?.messages.last?.text) {
                if let last = model.session?.messages.last?.id {
                    proxy.scrollTo(last)
                }
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 6) {
            if !model.lastError.isEmpty {
                Label(model.lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isConnected {
                VoiceComposer(
                    input: $input,
                    micOn: model.micOn,
                    onSend: submit,
                    onMic: { model.toggleMic() },
                    onEnd: { model.disconnect() }
                )
                if !model.eventLog.isEmpty {
                    HStack {
                        Text(model.eventLog.suffix(4).joined(separator: "  ->  "))
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Label("\(model.bytesPlayed / 1024) KB", systemImage: "speaker.wave.2")
                            .accessibilityLabel("Audio played: \(model.bytesPlayed / 1024) kilobytes")
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                }
            } else {
                ConnectBar(
                    isBusy: model.isBusy,
                    providerLabel: model.provider.shortLabel,
                    keyName: model.provider.keyName,
                    hasKey: !model.resolvedKey().isEmpty
                ) {
                    Task { await model.connect() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func submit() {
        model.sendText(input)
        input = ""
    }

    private func runSmokeIfRequested() async {
        guard CommandLine.arguments.contains("--smoke") else { return }
        guard !model.resolvedKey().isEmpty else {
            print("SMOKE SKIPPED: \(model.provider.keyName) is not set")
            exit(2)
        }
        print("smoke: connecting to \(model.provider.rawValue)")
        await model.connect()

        let connected = await waitUntil(seconds: 20) { model.statusLine == "connected" }
        print("smoke: connected=\(connected)")
        guard connected else {
            print("smoke: last error: \(model.lastError)")
            print("SMOKE FAILED")
            exit(1)
        }

        print("smoke: asking for a spoken answer")
        model.sendText("Please just say the word hello.")
        let gotAnswer = await waitUntil(seconds: 40) {
            let assistantText = model.session?.messages
                .filter { $0.role == .assistant }
                .map(\.text).joined() ?? ""
            return !assistantText.isEmpty && model.bytesPlayed > 0
        }
        let transcript = model.session?.messages
            .filter { $0.role == .assistant }.map(\.text).joined() ?? ""
        print("smoke: transcriptChars=\(transcript.count) audioBytes=\(model.bytesPlayed)")
        print("smoke: transcript: \(transcript.prefix(120))")

        print("smoke: asking the model to use the client tool")
        model.sendText("Use the getTime tool and tell me the time.")
        let toolUsed = await waitUntil(seconds: 40) { !model.lastToolCall.isEmpty }
        print("smoke: toolCall=\(model.lastToolCall.isEmpty ? "none" : model.lastToolCall)")

        model.disconnect()
        if gotAnswer && toolUsed {
            print("SMOKE PASSED")
            exit(0)
        }
        print("SMOKE \(gotAnswer ? "PARTIAL: tool call not observed" : "FAILED")")
        exit(gotAnswer ? 0 : 1)
    }

    private func waitUntil(
        seconds: Int, _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<(seconds * 4) {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return condition()
    }
}

struct EmptyVoiceView: View {
    let isConnected: Bool
    let providerLabel: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isConnected ? "waveform" : "waveform.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: isConnected)
            Text(isConnected ? "Listening" : "Talk to \(providerLabel)")
                .font(.title2.weight(.semibold))
            Text(
                isConnected
                    ? "Say something, or type below."
                    : "A live voice conversation over WebSockets, with speech both ways."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

struct ConnectBar: View {
    let isBusy: Bool
    let providerLabel: String
    let keyName: String
    let hasKey: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onConnect) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(sendIconColor)
                    }
                    Text(isBusy ? "Connecting" : "Connect to \(providerLabel)")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(sendIconColor)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .prominentGlassButtonStyle()
            .disabled(isBusy)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(isBusy ? "Connecting" : "Connect")

            Text(hasKey ? "Using \(keyName)" : "Add an API key in settings, or export \(keyName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct VoiceComposer: View {
    @Binding var input: String
    let micOn: Bool
    let onSend: () -> Void
    let onMic: () -> Void
    let onEnd: () -> Void

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressableButtonStyle())
            .glassChip(cornerRadius: 18, interactive: true)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("End conversation")

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask anything", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...4)
                    .padding(.leading, 6)
                    .padding(.vertical, 10)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .accessibilityLabel("Message")

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(sendIconColor)
                        .frame(width: 32, height: 32)
                        .background(.primary, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.35)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassChip(cornerRadius: 26)

            Button(action: onMic) {
                Image(systemName: micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(micOn ? .red : .secondary)
                    .frame(width: 36, height: 36)
                    .symbolEffect(.pulse, isActive: micOn)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .glassChip(cornerRadius: 18, interactive: true)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(micOn ? "Turn microphone off" : "Turn microphone on")
        }
    }
}

struct SettingsSheet: View {
    @Bindable var model: RealtimeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $model.provider) {
                        ForEach(RealtimeViewModel.Provider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    SecureField("API key", text: $model.apiKey)
                        .accessibilityLabel("API key")
                } header: {
                    Text("API key")
                } footer: {
                    Text("Leave empty to use \(model.provider.keyName) from the environment. The key mints a short-lived client secret; in production, mint it on your server.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct StatusPill: View {
    let status: String

    private var color: Color {
        switch status {
        case "connected": return .green
        case "error": return .red
        case "disconnected": return .secondary.opacity(0.6)
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(status)")
    }
}

struct RealtimeMessageView: View {
    let message: UIMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    if text.text.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Waiting for the model")
                    } else if message.role == .user {
                        Text(text.text)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(userBubbleColor, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        Text(text.text)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                case .tool(let tool):
                    Label(
                        "\(tool.toolName.isEmpty ? "tool" : tool.toolName): \(tool.state.rawValue)",
                        systemImage: "wrench.and.screwdriver"
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(noteFillColor, in: Capsule())
                default:
                    EmptyView()
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.role == .user ? .trailing : .leading
        )
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

var userBubbleColor: Color {
    #if os(iOS)
    Color(.systemGray5)
    #else
    Color(nsColor: .underPageBackgroundColor)
    #endif
}

var noteFillColor: Color {
    #if os(iOS)
    Color(.tertiarySystemFill)
    #else
    Color(nsColor: .underPageBackgroundColor)
    #endif
}

var sendIconColor: Color {
    #if os(iOS)
    Color(.systemBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
}

extension View {
    @ViewBuilder
    func glassChip(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

#Preview("Realtime") {
    RealtimeView()
}
