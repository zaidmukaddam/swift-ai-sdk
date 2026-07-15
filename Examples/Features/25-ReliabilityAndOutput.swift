import AI

enum ReliabilityExamples {
    struct Person: Decodable, Sendable { let name: String; let role: String }

    static func repairToolCalls() async throws {
        let weather = Tool(
            name: "get_weather",
            description: "Look up the weather for a city.",
            parameters: Schema.object(["city": .string()])
        ) { args in .string("Sunny in \(args["city"]?.stringValue ?? "?")") }

        let result = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "What's the weather in Tokyo?",
            tools: [weather],
            repairToolCall: { call, _ in
                call.name == "get_wether"
                    ? ToolCall(id: call.id, name: "get_weather", arguments: call.arguments) : nil
            }
        )
        print(result.text)
    }

    static func repairMalformedJSON() async throws {
        let result = try await generateObject(
            model: OpenAIModel("gpt-5.6-sol"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema.jsonSchema,
            prompt: "Summarize the benefits of Swift concurrency.",
            repairText: { text, _ in
                text.replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
            }
        )
        print(result.object.title)
    }

    static func structuredArray() async throws {
        let people = try await generateObjectArray(
            model: OpenAIModel("gpt-5.6-sol"),
            of: Person.self,
            elementSchema: Schema.object(["name": .string(), "role": .string()]).jsonSchema,
            prompt: "Invent three fictional startup founders."
        )
        print(people.object.map(\.name))
    }

    static func structuredAlongsideTools() async throws {
        let result = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "Give me a title and bullets about the library.",
            output: exampleSummarySchema.jsonSchema
        )
        print(result.experimentalOutput?["title"] ?? .null)
    }
}
