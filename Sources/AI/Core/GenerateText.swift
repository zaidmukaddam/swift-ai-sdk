import Foundation

public struct GenerateTextResult: Sendable {
    public var text: String
    public var reasoningText: String
    public var toolCalls: [ToolCall]
    public var toolResults: [ToolResult]
    public var sources: [Source]
    public var steps: [StepResult]
    public var messages: [Message]
    public var providerMetadata: JSONValue?
    public var experimentalOutput: JSONValue? = nil
    public var finishReason: FinishReason
    public var usage: Usage

    public var stepCount: Int { steps.count }
}

public func generateText(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    tools: [any AIToolProtocol] = [],
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    toolOrder: [String]? = nil,
    toolsContext: [String: JSONValue] = [:],
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    presencePenalty: Double? = nil,
    frequencyPenalty: Double? = nil,
    seed: Int? = nil,
    reasoning: ReasoningEffort = .providerDefault,
    stopSequences: [String] = [],
    providerOptions: JSONValue? = nil,
    stopWhen: [StopCondition]? = nil,
    maxSteps: Int = 8,
    prepareCall: PrepareCall? = nil,
    prepareStep: PrepareStep? = nil,
    onStepFinish: OnStepFinish? = nil,
    onFinish: (@Sendable (GenerateTextResult) async -> Void)? = nil,
    onError: (@Sendable (Error) async -> Void)? = nil,
    repairToolCall: (@Sendable (ToolCall, [any AIToolProtocol]) async -> ToolCall?)? = nil,
    output: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateTextResult {
    let parameters = GenerationParameters(
        model: model,
        messages: assembleMessages(messages: messages, system: system, prompt: prompt),
        tools: tools,
        toolChoice: toolChoice,
        activeTools: activeTools,
        toolsContext: toolsContext,
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        presencePenalty: presencePenalty,
        frequencyPenalty: frequencyPenalty,
        seed: seed,
        reasoning: reasoning,
        stopSequences: stopSequences,
        responseFormat: output.map { .json(schema: $0, name: "output", description: nil) } ?? .text,
        providerOptions: providerOptions,
        stopConditions: stopWhen ?? [.stepCountIs(max(1, maxSteps))],
        toolOrder: toolOrder,
        prepareCall: prepareCall,
        prepareStep: prepareStep,
        onStepFinish: onStepFinish,
        repairToolCall: repairToolCall,
        maxRetries: maxRetries
    )

    do {
        let result = try await AITelemetry.span(
            "ai.generateText",
            attributes: [
                "ai.model.provider": .string(model.provider),
                "ai.model.id": .string(model.modelID)
            ],
            endAttributes: { (result: GenerateTextResult) in
                [
                    "ai.usage.inputTokens": .number(Double(result.usage.inputTokens)),
                    "ai.usage.outputTokens": .number(Double(result.usage.outputTokens)),
                    "ai.response.finishReason": .string(result.finishReason.rawValue),
                    "ai.steps": .number(Double(result.stepCount))
                ]
            }
        ) {
            let outcome = try await runGenerationLoop(parameters) { _ in }
            var built = GenerateTextResult(outcome: outcome)
            if output != nil {
                if let data = built.text.data(using: .utf8),
                   let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    built.experimentalOutput = value
                } else {
                    built.experimentalOutput = PartialJSON.parse(built.text)
                }
            }
            return built
        }
        await onFinish?(result)
        return result
    } catch {
        await onError?(error)
        throw error
    }
}

extension GenerateTextResult {
    init(outcome: GenerationOutcome) {
        let lastStep = outcome.steps.last
        self.init(
            text: lastStep?.text ?? "",
            reasoningText: lastStep?.reasoningText ?? "",
            toolCalls: outcome.steps.flatMap(\.toolCalls),
            toolResults: outcome.steps.flatMap(\.toolResults),
            sources: outcome.steps.flatMap(\.sources),
            steps: outcome.steps,
            messages: outcome.messages,
            providerMetadata: outcome.steps.compactMap(\.providerMetadata).reduce(nil) {
                JSONValue.mergingMetadata($0, $1)
            },
            finishReason: outcome.finishReason,
            usage: outcome.totalUsage
        )
    }
}

public func streamTextDeltas(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil
) -> AsyncThrowingStream<String, Error> {
    streamText(
        model: model, messages: messages, system: system, prompt: prompt,
        maxOutputTokens: maxOutputTokens, temperature: temperature
    ).textStream
}
