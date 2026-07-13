# Structured output

`generateObject` constrains model output to a schema and decodes it into your `Codable` type; malformed output throws `AIError` instead of producing a corrupt value. All functions are top-level in `import AI`. Each provider uses its best native mechanism (JSON-schema mode on OpenAI, constrained decoding on Gemini and on-device, a forced tool call on Anthropic) behind one call site.

## generateObject

Two overloads: one takes a raw `JSONValue` schema, the other a `Schema` DSL value (which additionally validates the decoded JSON before returning).

```swift
public func generateObject<T: Decodable & Sendable>(
    model: any LanguageModel,
    of type: T.Type = T.self,
    schema: JSONValue,
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateObjectResult<T>

public func generateObject<T: Decodable & Sendable>(
    model: any LanguageModel,
    of type: T.Type = T.self,
    schema: Schema,               // Schema DSL overload; also runs schema.validate
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateObjectResult<T>
```

```swift
public struct GenerateObjectResult<T: Sendable>: Sendable {
    public var object: T
    public var rawJSON: JSONValue
    public var finishReason: FinishReason
    public var usage: Usage
}
```

```swift
import AI

struct Recipe: Codable {
    var name: String
    var ingredients: [String]
    var steps: [String]
}

let result = try await generateObject(
    model: OpenAIModel("gpt-5.6-sol"),
    of: Recipe.self,
    schema: Schema.object([
        "name": .string(description: "Recipe name"),
        "ingredients": .array(of: .string()),
        "steps": .array(of: .string(), minItems: 1)
    ]),
    prompt: "A simple lasagna recipe."
)
print(result.object.name)
```

## The Schema DSL

`Schema` builds JSON Schema and, on the `Schema` overloads, validates the model's output at runtime before decoding.

```swift
public struct Schema: Sendable {
    public let jsonSchema: JSONValue

    public static func raw(_ jsonSchema: JSONValue) -> Schema
    public static func string(description: String? = nil, enum choices: [String]? = nil,
                              pattern: String? = nil, format: String? = nil) -> Schema
    public static func number(description: String? = nil,
                              minimum: Double? = nil, maximum: Double? = nil) -> Schema
    public static func integer(description: String? = nil,
                               minimum: Int? = nil, maximum: Int? = nil) -> Schema
    public static func boolean(description: String? = nil) -> Schema
    public static func null() -> Schema
    public static func array(of element: Schema, description: String? = nil,
                             minItems: Int? = nil, maxItems: Int? = nil) -> Schema
    public static func object(_ properties: [String: Schema], description: String? = nil,
                              additionalProperties: Bool = false) -> Schema
    public static func `enum`(_ values: [String], description: String? = nil) -> Schema
    public static func anyOf(_ alternatives: [Schema], description: String? = nil) -> Schema

    public func optional() -> Schema         // marks a property non-required
    public func describe(_ text: String) -> Schema
    public func validate(_ value: JSONValue) throws
}
```

Object properties are required by default; call `.optional()` on a property to drop it from `required`. `additionalProperties` defaults to `false`.

```swift
let event = Schema.object([
    "kind": .enum(["meeting", "reminder"]),
    "when": .string(format: "date-time"),
    "servings": .integer(minimum: 1).optional(),
    "attendees": .array(of: .object([
        "name": .string(),
        "id": .anyOf([.integer(), .string()])
    ])).optional()
])
```

The same `Schema` values plug into `Tool(parameters:)`, where arguments are validated before your closure runs.

## streamObject

Repairs partial JSON as it arrives so a form can fill itself in while the model writes. Like `streamText`, it is synchronous and lazy. Overloads for `JSONValue` and `Schema` schemas.

```swift
public func streamObject(
    model: any LanguageModel,
    schema: JSONValue,               // (also a Schema overload)
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) -> StreamObjectResult

public struct StreamObjectResult: Sendable {
    public let partialObjectStream: AsyncThrowingStream<JSONValue, Error>
    public func elementStream() -> AsyncThrowingStream<JSONValue, Error>
}
```

```swift
let result = streamObject(
    model: model,
    schema: recipeSchema,
    prompt: "A simple lasagna recipe."
)

var latest: JSONValue = .null
for try await partial in result.partialObjectStream {
    latest = partial
    render(partial)
}
let recipe = try latest.decode(Recipe.self)
```

The last snapshot yielded by `partialObjectStream` is the complete object.

### elementStream (arrays)

For array-shaped schemas, `elementStream()` yields each completed array element exactly once, in order — an element counts as complete once the model moves on to the next (or the stream ends). It is derived from `partialObjectStream`, so consume one or the other, not both. Non-array schemas produce an empty stream.

```swift
let result = streamObject(model: model, schema: heroListSchema, prompt: "3 heroes")
for try await hero in result.elementStream() {
    rows.append(hero)
}
```

## generateEnum

Picks one of a fixed set of strings. Good for classification.

```swift
public struct GenerateEnumResult: Sendable {
    public var value: String
    public var finishReason: FinishReason
    public var usage: Usage
}

public func generateEnum(
    model: any LanguageModel,
    values: [String],
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateEnumResult
```

```swift
let sentiment = try await generateEnum(
    model: model,
    values: ["positive", "neutral", "negative"],
    prompt: "Classify: this library is delightful."
)
print(sentiment.value)
```

The parameter is `values:` (not `cases:`). An empty `values` throws `AIError.invalidRequest`; a returned value outside the set throws `AIError.noObjectGenerated`.

## generateJSON

Any valid JSON, no schema. Injects a "respond only with valid JSON" instruction into the system prompt.

```swift
public func generateJSON(
    model: any LanguageModel,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateObjectResult<JSONValue>
```

```swift
let palette = try await generateJSON(model: model, prompt: "A color palette as JSON.")
print(palette.object["colors"]?.arrayValue?.count ?? 0)
```

## Errors instead of crashes

Bad output surfaces as a thrown `AIError`, never a crash or a corrupt value:

- No parseable object in the response → `AIError.noObjectGenerated(rawText)`.
- Object parses but fails to decode into `T` → `AIError.noObjectGenerated("Decoding failed: …")`.
- `Schema` overload: decoded JSON fails `schema.validate` → `AIError.noObjectGenerated("Schema validation failed: …")`.
- `Schema.validate` itself throws `AIError.decoding` with a JSON-path message (e.g. `$.servings: expected integer`).

```swift
do {
    let result = try await generateObject(model: model, of: Recipe.self,
                                          schema: recipeSchema, prompt: prompt)
    use(result.object)
} catch let error as AIError {
    handle(error)
}
```

## Gotchas

- `streamObject` is lazy and synchronous; nothing runs until you iterate. Consume `partialObjectStream` **or** `elementStream()`, not both.
- Only the `Schema` overloads run runtime validation. The raw-`JSONValue` overloads rely on the provider plus `Codable` decoding.
- `Schema.object` properties are required unless you call `.optional()`; `additionalProperties` defaults to `false`, so unexpected keys fail validation.
- `generateEnum` uses `values:`, not `cases:`.
- `describe(_:)` only attaches a description to object-typed schemas; on non-object schemas it returns the schema unchanged. To describe a scalar, pass `description:` to its factory (e.g. `.string(description:)`).
- `generateObject` decodes from a structured tool call when the provider forces one, otherwise from the assembled text; `rawJSON` holds whichever was used.
