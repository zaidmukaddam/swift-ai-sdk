import AI

struct Recipe: Codable {
    var name: String
    var ingredients: [String]
    var steps: [String]
}

let recipeSchema: JSONValue = [
    "type": "object",
    "properties": [
        "name": ["type": "string"],
        "ingredients": ["type": "array", "items": ["type": "string"]],
        "steps": ["type": "array", "items": ["type": "string"]]
    ],
    "required": ["name", "ingredients", "steps"]
]

func example_generateObject() async throws {
    let model = OpenAIModel("gpt-5.6-sol", apiKey: openAIKey)

    let result = try await generateObject(
        model: model,
        of: Recipe.self,
        schema: recipeSchema,
        prompt: "A simple lasagna recipe."
    )

    print(result.object.name, "with", result.object.steps.count, "steps")
}
