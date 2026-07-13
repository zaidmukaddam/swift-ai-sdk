import AI

struct TypedRecipe: Codable {
    var name: String
    var steps: [String]
    var servings: Int?
}

let typedRecipeSchema = Schema.object([
    "name": .string(description: "Recipe name"),
    "steps": .array(of: .string(), minItems: 1),
    "servings": .integer(minimum: 1).optional()
])

func example_schema() async throws {
    let result = try await generateObject(
        model: OpenAIModel("gpt-5.6-sol"),
        of: TypedRecipe.self,
        schema: typedRecipeSchema,
        prompt: "A simple dal recipe."
    )
    print(result.object.name, "-", result.object.steps.count, "steps")
}

func example_schemaTools() async throws {
    let serve = Tool(
        name: "serve",
        description: "Serve a number of portions",
        parameters: Schema.object(["servings": .integer(minimum: 1)])
    ) { args in
        .string("served \(args["servings"]?.intValue ?? 0)")
    }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "Serve dinner for four.",
        tools: [serve]
    )
    print(result.text)
}

func example_schemaShapes() {
    let event = Schema.object([
        "kind": .enum(["meeting", "reminder"]),
        "when": .string(format: "date-time"),
        "attendees": .array(of: .object([
            "name": .string(),
            "id": .anyOf([.integer(), .string()])
        ])).optional()
    ])
    print(event.jsonSchema)

    do {
        try event.validate(["kind": "meeting", "when": "2026-07-12T10:00:00Z"])
        print("valid")
    } catch {
        print("invalid:", error)
    }
}
