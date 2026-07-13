import AI
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct StreamTextDemoApp: App {
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
            ChatView()
        }
    }
}

@Observable @MainActor
final class ChatModel {
    struct Entry: Identifiable {
        enum Kind { case user, assistant, note }
        let id = UUID()
        var kind: Kind
        var text: String
    }

    var entries: [Entry] = []
    var isStreaming = false
    let modelID: String
    let host: String

    private var history: [Message] = []
    private let model: OpenAIChatModel

    init() {
        let environment = ProcessInfo.processInfo.environment
        modelID = environment["OLLAMA_MODEL"] ?? "granite4.1:3b"
        host = environment["OLLAMA_HOST"] ?? "http://localhost:11434"
        model = OpenAICompatibleProvider.ollama(
            baseURL: URL(string: "\(host)/v1")!
        )(modelID)
    }

    private var weatherTool: Tool {
        Tool(
            name: "weather",
            description: "Get the current weather for a city.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "city": .object([
                        "type": .string("string"),
                        "description": .string("The city name.")
                    ])
                ]),
                "required": .array([.string("city")])
            ])
        ) { arguments in
            let city = arguments["city"]?.stringValue ?? "somewhere"
            return .object([
                "city": .string(city),
                "condition": .string("sunny"),
                "temperatureC": .number(31)
            ])
        }
    }

    @discardableResult
    func send(_ prompt: String) async -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return "" }

        entries.append(Entry(kind: .user, text: trimmed))
        let live = Entry(kind: .assistant, text: "")
        entries.append(live)
        isStreaming = true
        defer { isStreaming = false }

        func liveIndex() -> Int? {
            entries.firstIndex { $0.id == live.id }
        }

        history.append(.user(trimmed))
        let result = streamText(
            model: model,
            messages: history,
            system: "You are a concise assistant. Use the weather tool for weather questions.",
            tools: [weatherTool],
            maxSteps: 4
        )
        do {
            for try await part in result.fullStream {
                switch part {
                case .textDelta(let delta):
                    if let index = liveIndex() { entries[index].text += delta }
                    print(delta, terminator: "")
                case .toolCall(let call):
                    if let index = liveIndex() {
                        entries.insert(
                            Entry(kind: .note, text: "tool call: \(call.name)(\(call.arguments))"),
                            at: index
                        )
                    }
                case .toolResult(let result):
                    if let index = liveIndex() {
                        entries.insert(
                            Entry(kind: .note, text: "tool result: \(result.output)"),
                            at: index
                        )
                    }
                case .finishStep(let step):
                    history.append(Message(
                        role: .assistant,
                        content: step.text.isEmpty && step.toolCalls.isEmpty
                            ? [.text("")]
                            : (step.text.isEmpty ? [] : [ContentPart.text(step.text)])
                                + step.toolCalls.map { ContentPart.toolCall($0) }
                    ))
                    if !step.toolResults.isEmpty {
                        history.append(Message(
                            role: .tool,
                            content: step.toolResults.map { .toolResult($0) }
                        ))
                    }
                default:
                    break
                }
            }
            print("")
        } catch {
            if let index = liveIndex() { entries[index].text += "\n[error: \(error)]" }
            print("error: \(error)")
        }
        let answer = liveIndex().map { entries[$0].text } ?? ""
        if answer.isEmpty { entries.removeAll { $0.id == live.id } }
        return answer
    }
}

struct ChatView: View {
    @State private var model = ChatModel()
    @State private var input = ""
    @State private var sendCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if model.entries.isEmpty {
                    EmptyChatView { suggestion in
                        input = suggestion
                        submit()
                    }
                } else {
                    conversation
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ModelMenu(modelID: model.modelID, host: model.host)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Composer(
                    input: $input,
                    isStreaming: model.isStreaming,
                    onSend: submit
                )
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount)
        .task { await runSmokeIfRequested() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.entries) { entry in
                        EntryView(entry: entry, isStreaming: model.isStreaming)
                            .id(entry.id)
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
                    value: model.entries.count
                )
            }
            .onChange(of: model.entries.count) {
                guard let lastUser = model.entries.last(where: { $0.kind == .user }) else {
                    return
                }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0)) {
                    proxy.scrollTo(lastUser.id, anchor: .top)
                }
            }
            .onChange(of: model.entries.last?.text) {
                if let last = model.entries.last?.id {
                    proxy.scrollTo(last)
                }
            }
        }
    }

    private func submit() {
        let text = input
        input = ""
        sendCount += 1
        Task { await model.send(text) }
    }

    private func runSmokeIfRequested() async {
        guard CommandLine.arguments.contains("--smoke") else { return }
        print("smoke: sending scripted prompt to \(model.modelID)")
        let answer = await model.send("What is the weather in Mumbai? Use the weather tool.")

        let sawToolCall = model.entries.contains {
            $0.kind == .note && $0.text.hasPrefix("tool call: weather")
        }
        print("smoke: toolCall=\(sawToolCall) answerChars=\(answer.count)")

        let followUp = await model.send("Thanks! Answer with one word: what city was that for?")
        print("smoke: followUpChars=\(followUp.count)")
        for (index, entry) in model.entries.enumerated() {
            print("smoke: entry[\(index)] \(entry.kind) \(entry.text.prefix(44))")
        }

        let passed = sawToolCall && !answer.isEmpty && !followUp.isEmpty
        print(passed ? "SMOKE PASSED" : "SMOKE FAILED")
        if CommandLine.arguments.contains("--hold") { return }
        exit(passed ? 0 : 1)
    }
}

struct ModelMenu: View {
    let modelID: String
    let host: String

    var body: some View {
        Menu {
            Section("Model") {
                Label(modelID, systemImage: "cpu")
                Label(host, systemImage: "server.rack")
            }
        } label: {
            HStack(spacing: 4) {
                Text("StreamText")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Model: \(modelID)")
    }
}

struct EmptyChatView: View {
    let onSuggestion: (String) -> Void

    private let suggestions = [
        "What is the weather in Mumbai?",
        "Explain streaming in one sentence",
        "Write a haiku about Swift"
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("What can I help with?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .glassChip(cornerRadius: 22, interactive: true)
                }
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

struct EntryView: View {
    let entry: ChatModel.Entry
    let isStreaming: Bool

    var body: some View {
        switch entry.kind {
        case .user:
            Text(entry.text)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(userBubbleColor, in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            if entry.text.isEmpty && isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for the model")
            } else {
                Text(entry.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .note:
            ToolNoteChip(text: entry.text)
        }
    }
}

struct ToolNoteChip: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "wrench.and.screwdriver")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(noteFillColor, in: Capsule())
            .accessibilityLabel("Tool activity: \(text)")
    }
}

struct Composer: View {
    @Binding var input: String
    let isStreaming: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
                Image(systemName: isStreaming ? "ellipsis" : "arrow.up")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(sendIconColor)
                    .frame(width: 32, height: 32)
                    .background(.primary, in: Circle())
                    .symbolEffect(.pulse, isActive: isStreaming)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSend)
            .opacity(canSend || isStreaming ? 1 : 0.35)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(isStreaming ? "Responding" : "Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .glassChip(cornerRadius: 26)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
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
}

#Preview("Chat") {
    ChatView()
}
