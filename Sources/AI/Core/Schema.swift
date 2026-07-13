import Foundation

public struct Schema: Sendable {
    public let jsonSchema: JSONValue
    let isRequired: Bool

    init(jsonSchema: JSONValue, isRequired: Bool = true) {
        self.jsonSchema = jsonSchema
        self.isRequired = isRequired
    }

    public static func raw(_ jsonSchema: JSONValue) -> Schema {
        Schema(jsonSchema: jsonSchema)
    }

    public static func string(
        description: String? = nil,
        enum choices: [String]? = nil,
        pattern: String? = nil,
        format: String? = nil
    ) -> Schema {
        var schema: [String: JSONValue] = ["type": "string"]
        if let description { schema["description"] = .string(description) }
        if let choices { schema["enum"] = .array(choices.map { .string($0) }) }
        if let pattern { schema["pattern"] = .string(pattern) }
        if let format { schema["format"] = .string(format) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func number(
        description: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> Schema {
        var schema: [String: JSONValue] = ["type": "number"]
        if let description { schema["description"] = .string(description) }
        if let minimum { schema["minimum"] = .number(minimum) }
        if let maximum { schema["maximum"] = .number(maximum) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func integer(
        description: String? = nil,
        minimum: Int? = nil,
        maximum: Int? = nil
    ) -> Schema {
        var schema: [String: JSONValue] = ["type": "integer"]
        if let description { schema["description"] = .string(description) }
        if let minimum { schema["minimum"] = .number(Double(minimum)) }
        if let maximum { schema["maximum"] = .number(Double(maximum)) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func boolean(description: String? = nil) -> Schema {
        var schema: [String: JSONValue] = ["type": "boolean"]
        if let description { schema["description"] = .string(description) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func null() -> Schema {
        Schema(jsonSchema: .object(["type": "null"]))
    }

    public static func array(
        of element: Schema,
        description: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> Schema {
        var schema: [String: JSONValue] = [
            "type": "array",
            "items": element.jsonSchema
        ]
        if let description { schema["description"] = .string(description) }
        if let minItems { schema["minItems"] = .number(Double(minItems)) }
        if let maxItems { schema["maxItems"] = .number(Double(maxItems)) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func object(
        _ properties: [String: Schema],
        description: String? = nil,
        additionalProperties: Bool = false
    ) -> Schema {
        var props: [String: JSONValue] = [:]
        var required: [String] = []
        for (key, property) in properties {
            props[key] = property.jsonSchema
            if property.isRequired { required.append(key) }
        }
        var schema: [String: JSONValue] = [
            "type": "object",
            "properties": .object(props),
            "required": .array(required.sorted().map { .string($0) }),
            "additionalProperties": .bool(additionalProperties)
        ]
        if let description { schema["description"] = .string(description) }
        return Schema(jsonSchema: .object(schema))
    }

    public static func `enum`(_ values: [String], description: String? = nil) -> Schema {
        string(description: description, enum: values)
    }

    public static func anyOf(_ alternatives: [Schema], description: String? = nil) -> Schema {
        var schema: [String: JSONValue] = [
            "anyOf": .array(alternatives.map(\.jsonSchema))
        ]
        if let description { schema["description"] = .string(description) }
        return Schema(jsonSchema: .object(schema))
    }

    public func optional() -> Schema {
        Schema(jsonSchema: jsonSchema, isRequired: false)
    }

    public func describe(_ text: String) -> Schema {
        guard case .object(var schema) = jsonSchema else { return self }
        schema["description"] = .string(text)
        return Schema(jsonSchema: .object(schema), isRequired: isRequired)
    }

    public func validate(_ value: JSONValue) throws {
        try Schema.check(value, against: jsonSchema, path: "$")
    }

    private static func check(
        _ value: JSONValue, against schema: JSONValue, path: String
    ) throws {
        if let alternatives = schema["anyOf"]?.arrayValue {
            for alternative in alternatives {
                if (try? check(value, against: alternative, path: path)) != nil { return }
            }
            throw AIError.decoding("\(path): no anyOf alternative matched")
        }

        if let choices = schema["enum"]?.arrayValue {
            guard choices.contains(value) else {
                throw AIError.decoding("\(path): value is not one of the allowed choices")
            }
            return
        }

        switch schema["type"]?.stringValue {
        case "string":
            guard case .string = value else {
                throw AIError.decoding("\(path): expected string")
            }
        case "number":
            guard case .number(let number) = value else {
                throw AIError.decoding("\(path): expected number")
            }
            try checkRange(number, schema: schema, path: path)
        case "integer":
            guard case .number(let number) = value,
                  number.truncatingRemainder(dividingBy: 1) == 0 else {
                throw AIError.decoding("\(path): expected integer")
            }
            try checkRange(number, schema: schema, path: path)
        case "boolean":
            guard case .bool = value else {
                throw AIError.decoding("\(path): expected boolean")
            }
        case "null":
            guard case .null = value else {
                throw AIError.decoding("\(path): expected null")
            }
        case "array":
            guard case .array(let items) = value else {
                throw AIError.decoding("\(path): expected array")
            }
            if let minItems = schema["minItems"]?.intValue, items.count < minItems {
                throw AIError.decoding("\(path): expected at least \(minItems) items")
            }
            if let maxItems = schema["maxItems"]?.intValue, items.count > maxItems {
                throw AIError.decoding("\(path): expected at most \(maxItems) items")
            }
            if let itemSchema = schema["items"] {
                for (index, item) in items.enumerated() {
                    try check(item, against: itemSchema, path: "\(path)[\(index)]")
                }
            }
        case "object":
            guard case .object(let object) = value else {
                throw AIError.decoding("\(path): expected object")
            }
            for name in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                guard object[name] != nil else {
                    throw AIError.decoding("\(path): missing required property \"\(name)\"")
                }
            }
            let properties = schema["properties"]?.objectValue ?? [:]
            for (key, propertyValue) in object {
                if let propertySchema = properties[key] {
                    try check(propertyValue, against: propertySchema, path: "\(path).\(key)")
                } else if schema["additionalProperties"]?.boolValue == false {
                    throw AIError.decoding("\(path): unexpected property \"\(key)\"")
                }
            }
        default:
            break
        }
    }

    private static func checkRange(
        _ number: Double, schema: JSONValue, path: String
    ) throws {
        if let minimum = schema["minimum"]?.doubleValue, number < minimum {
            throw AIError.decoding("\(path): \(number) is below the minimum \(minimum)")
        }
        if let maximum = schema["maximum"]?.doubleValue, number > maximum {
            throw AIError.decoding("\(path): \(number) is above the maximum \(maximum)")
        }
    }
}

public func generateObject<T: Decodable & Sendable>(
    model: any LanguageModel,
    of type: T.Type = T.self,
    schema: Schema,
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateObjectResult<T> {
    let result = try await generateObject(
        model: model, of: type, schema: schema.jsonSchema,
        schemaName: schemaName, schemaDescription: schemaDescription,
        messages: messages, system: system, prompt: prompt,
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries
    )
    do {
        try schema.validate(result.rawJSON)
    } catch {
        throw AIError.noObjectGenerated("Schema validation failed: \(error)")
    }
    return result
}

public func streamObject(
    model: any LanguageModel,
    schema: Schema,
    schemaName: String = "response",
    schemaDescription: String? = nil,
    messages: [Message] = [],
    system: String? = nil,
    prompt: String? = nil,
    maxOutputTokens: Int = 1024,
    temperature: Double? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) -> StreamObjectResult {
    streamObject(
        model: model, schema: schema.jsonSchema,
        schemaName: schemaName, schemaDescription: schemaDescription,
        messages: messages, system: system, prompt: prompt,
        maxOutputTokens: maxOutputTokens, temperature: temperature,
        providerOptions: providerOptions, maxRetries: maxRetries
    )
}

public extension Tool {
    init(
        name: String,
        description: String,
        parameters: Schema,
        needsApproval: Bool = false,
        execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) {
        self.init(
            name: name, description: description,
            parameters: parameters.jsonSchema,
            needsApproval: needsApproval
        ) { arguments in
            try parameters.validate(arguments)
            return try await execute(arguments)
        }
    }
}
