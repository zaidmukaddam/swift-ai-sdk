import Foundation

public struct Agent: Sendable {
    public var model: any LanguageModel
    public var instructions: String?
    public var tools: [any AIToolProtocol]
    public var toolChoice: ToolChoice
    public var activeTools: [String]?
    public var toolOrder: [String]?
    public var toolsContext: [String: JSONValue]
    public var maxOutputTokens: Int
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var seed: Int?
    public var reasoning: ReasoningEffort
    public var stopWhen: [StopCondition]?
    public var maxSteps: Int
    public var prepareCall: PrepareCall?
    public var prepareStep: PrepareStep?
    public var onStepFinish: OnStepFinish?
    public var maxRetries: Int
    public var providerOptions: JSONValue?

    public init(
        model: any LanguageModel,
        instructions: String? = nil,
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
        stopWhen: [StopCondition]? = nil,
        maxSteps: Int = 8,
        prepareCall: PrepareCall? = nil,
        prepareStep: PrepareStep? = nil,
        onStepFinish: OnStepFinish? = nil,
        maxRetries: Int = 2,
        providerOptions: JSONValue? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.activeTools = activeTools
        self.toolOrder = toolOrder
        self.toolsContext = toolsContext
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.reasoning = reasoning
        self.stopWhen = stopWhen
        self.maxSteps = maxSteps
        self.prepareCall = prepareCall
        self.prepareStep = prepareStep
        self.onStepFinish = onStepFinish
        self.maxRetries = maxRetries
        self.providerOptions = providerOptions
    }

    public func generate(prompt: String) async throws -> GenerateTextResult {
        try await generateText(
            model: model,
            system: instructions,
            prompt: prompt,
            tools: tools,
            toolChoice: toolChoice,
            activeTools: activeTools,
            toolOrder: toolOrder,
            toolsContext: toolsContext,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            reasoning: reasoning,
            providerOptions: providerOptions,
            stopWhen: stopWhen,
            maxSteps: maxSteps,
            prepareCall: prepareCall,
            prepareStep: prepareStep,
            onStepFinish: onStepFinish,
            maxRetries: maxRetries
        )
    }

    public func generate(messages: [Message]) async throws -> GenerateTextResult {
        try await generateText(
            model: model,
            messages: messages,
            system: instructions,
            tools: tools,
            toolChoice: toolChoice,
            activeTools: activeTools,
            toolOrder: toolOrder,
            toolsContext: toolsContext,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            reasoning: reasoning,
            providerOptions: providerOptions,
            stopWhen: stopWhen,
            maxSteps: maxSteps,
            prepareCall: prepareCall,
            prepareStep: prepareStep,
            onStepFinish: onStepFinish,
            maxRetries: maxRetries
        )
    }

    public func stream(prompt: String) -> StreamTextResult {
        streamText(
            model: model,
            system: instructions,
            prompt: prompt,
            tools: tools,
            toolChoice: toolChoice,
            activeTools: activeTools,
            toolOrder: toolOrder,
            toolsContext: toolsContext,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            reasoning: reasoning,
            providerOptions: providerOptions,
            stopWhen: stopWhen,
            maxSteps: maxSteps,
            prepareCall: prepareCall,
            prepareStep: prepareStep,
            onStepFinish: onStepFinish,
            maxRetries: maxRetries
        )
    }

    public func stream(messages: [Message]) -> StreamTextResult {
        streamText(
            model: model,
            messages: messages,
            system: instructions,
            tools: tools,
            toolChoice: toolChoice,
            activeTools: activeTools,
            toolOrder: toolOrder,
            toolsContext: toolsContext,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            reasoning: reasoning,
            providerOptions: providerOptions,
            stopWhen: stopWhen,
            maxSteps: maxSteps,
            prepareCall: prepareCall,
            prepareStep: prepareStep,
            onStepFinish: onStepFinish,
            maxRetries: maxRetries
        )
    }
}

public extension Agent {
    func asTool(
        name: String,
        description: String,
        promptDescription: String = "The task for the agent to perform."
    ) -> Tool {
        let agent = self
        return Tool(
            name: name,
            description: description,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "prompt": .object([
                        "type": .string("string"),
                        "description": .string(promptDescription)
                    ])
                ]),
                "required": .array([.string("prompt")])
            ])
        ) { arguments in
            guard case .string(let prompt)? = arguments["prompt"] else {
                throw AIError.invalidRequest("Subagent tool \"\(name)\" requires a string \"prompt\" argument")
            }
            let result = try await agent.generate(prompt: prompt)
            return .string(result.text)
        }
    }
}

extension Agent: ChatTransport {
    public func sendMessages(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<UIMessageChunk, Error> {
        var messages = request.messages
        if request.trigger == .regenerateMessage {
            if let targetID = request.messageID,
               let index = messages.firstIndex(where: { $0.id == targetID }) {
                messages = Array(messages[..<index])
            } else if messages.last?.role == .assistant {
                messages.removeLast()
            }
        }

        let result = stream(messages: convertToModelMessages(messages))
        return UIMessageStream.chunks(from: result.fullStream, messageID: UUID().uuidString)
    }
}
