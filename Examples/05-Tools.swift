import AI

func example_tools() async throws {
    let getTime = Tool(
        name: "current_time",
        description: "Returns the current time in a timezone.",
        parameters: ["type": "object",
                     "properties": ["tz": ["type": "string"]],
                     "required": ["tz"]]
    ) { args in
        .string("2026-07-11T14:00 \(args["tz"]?.stringValue ?? "UTC")")
    }

    let model = AnthropicModel("claude-opus-4-8", apiKey: myKey)
    let result = try await generateText(
        model: model,
        prompt: "What time is it in Asia/Kolkata?",
        tools: [getTime],
        stopWhen: [stepCountIs(4)],
        onStepFinish: { step in print("step:", step.finishReason) }
    )

    print(result.text)
    print("steps: \(result.stepCount)")
}

func example_typedTool() -> Tool {
    struct WeatherArgs: Decodable {
        var city: String
    }
    return Tool.typed(
        name: "weather",
        description: "Current weather for a city",
        parameters: ["type": "object",
                     "properties": ["city": ["type": "string"]],
                     "required": ["city"]]
    ) { (args: WeatherArgs) in
        ["tempC": 31, "city": .string(args.city)]
    }
}

func example_prepareStep() async throws {
    let big = AnthropicModel("claude-opus-4-8", apiKey: myKey)
    let small = AnthropicModel("claude-haiku-4-5-20251001", apiKey: myKey)

    let result = try await generateText(
        model: big,
        prompt: "Research something that takes many tool calls.",
        tools: [example_typedTool()],
        stopWhen: [stepCountIs(10)],
        prepareStep: { context in
            context.stepNumber >= 3 ? PrepareStepResult(model: small) : nil
        }
    )
    print(result.text)
}
