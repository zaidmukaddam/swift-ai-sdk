import AI

func example_streamObject() async throws {
    let model = OpenAIModel("gpt-5.6-sol", apiKey: openAIKey)

    let result = streamObject(
        model: model,
        schema: recipeSchema,
        prompt: "A simple lasagna recipe."
    )

    var latest: JSONValue = .null
    for try await partial in result.partialObjectStream {
        latest = partial
        print("so far:", partial["name"]?.stringValue ?? "...")
    }

    let recipe = try latest.decode(Recipe.self)
    print("done:", recipe.name)
}
