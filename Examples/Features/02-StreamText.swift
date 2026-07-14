import AI

func example_stream() async throws {
    let model = AnthropicModel("claude-sonnet-5", apiKey: myKey)

    let result = streamText(model: model, prompt: "Write a haiku about Swift.")
    for try await delta in result.textStream {
        print(delta, terminator: "")
    }
}

func example_fullStream() async throws {
    let model = AnthropicModel("claude-sonnet-5", apiKey: myKey)

    for try await part in streamText(model: model, prompt: "Hi!").fullStream {
        switch part {
        case .textDelta(let delta): print(delta, terminator: "")
        case .finishStep(let step): print("\n[step done: \(step.finishReason)]")
        case .finish(let reason, let usage): print("[\(reason), \(usage.totalTokens) tokens]")
        default: break
        }
    }
}
