import Foundation

public struct ProviderRegistry: Sendable {

    public struct Provider: Sendable {
        var languageModel: (@Sendable (String) throws -> any LanguageModel)?
        var embeddingModel: (@Sendable (String) throws -> any EmbeddingModel)?
        var imageModel: (@Sendable (String) throws -> any ImageModel)?
        var speechModel: (@Sendable (String) throws -> any SpeechModel)?
        var transcriptionModel: (@Sendable (String) throws -> any TranscriptionModel)?
        var rerankingModel: (@Sendable (String) throws -> any RerankingModel)?

        public init(
            languageModel: (@Sendable (String) throws -> any LanguageModel)? = nil,
            embeddingModel: (@Sendable (String) throws -> any EmbeddingModel)? = nil,
            imageModel: (@Sendable (String) throws -> any ImageModel)? = nil,
            speechModel: (@Sendable (String) throws -> any SpeechModel)? = nil,
            transcriptionModel: (@Sendable (String) throws -> any TranscriptionModel)? = nil,
            rerankingModel: (@Sendable (String) throws -> any RerankingModel)? = nil
        ) {
            self.languageModel = languageModel
            self.embeddingModel = embeddingModel
            self.imageModel = imageModel
            self.speechModel = speechModel
            self.transcriptionModel = transcriptionModel
            self.rerankingModel = rerankingModel
        }

        public init(_ languageModel: @escaping @Sendable (String) throws -> any LanguageModel) {
            self.init(languageModel: languageModel)
        }
    }

    private let providers: [String: Provider]
    private let separator: String

    public init(providers: [String: Provider], separator: String = ":") {
        self.providers = providers
        self.separator = separator
    }

    public func languageModel(_ id: String) throws -> any LanguageModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).languageModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no language models")
        }
        return try factory(modelID)
    }

    public func embeddingModel(_ id: String) throws -> any EmbeddingModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).embeddingModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no embedding models")
        }
        return try factory(modelID)
    }

    public func imageModel(_ id: String) throws -> any ImageModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).imageModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no image models")
        }
        return try factory(modelID)
    }

    public func speechModel(_ id: String) throws -> any SpeechModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).speechModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no speech models")
        }
        return try factory(modelID)
    }

    public func transcriptionModel(_ id: String) throws -> any TranscriptionModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).transcriptionModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no transcription models")
        }
        return try factory(modelID)
    }

    public func rerankingModel(_ id: String) throws -> any RerankingModel {
        let (provider, modelID) = try split(id)
        guard let factory = try lookup(provider).rerankingModel else {
            throw AIError.invalidRequest("Provider \"\(provider)\" has no reranking models")
        }
        return try factory(modelID)
    }

    private func split(_ id: String) throws -> (provider: String, modelID: String) {
        guard let range = id.range(of: separator) else {
            throw AIError.invalidRequest(
                "Invalid model id \"\(id)\": expected \"provider\(separator)model\""
            )
        }
        let provider = String(id[..<range.lowerBound])
        let modelID = String(id[range.upperBound...])
        guard !provider.isEmpty, !modelID.isEmpty else {
            throw AIError.invalidRequest(
                "Invalid model id \"\(id)\": expected \"provider\(separator)model\""
            )
        }
        return (provider, modelID)
    }

    private func lookup(_ provider: String) throws -> Provider {
        guard let entry = providers[provider] else {
            throw AIError.invalidRequest("No provider registered for \"\(provider)\"")
        }
        return entry
    }
}

public func customProvider(
    languageModels: [String: any LanguageModel] = [:],
    embeddingModels: [String: any EmbeddingModel] = [:],
    imageModels: [String: any ImageModel] = [:],
    speechModels: [String: any SpeechModel] = [:],
    transcriptionModels: [String: any TranscriptionModel] = [:],
    rerankingModels: [String: any RerankingModel] = [:],
    fallback: ProviderRegistry.Provider? = nil
) -> ProviderRegistry.Provider {
    func compose<M>(
        _ aliases: [String: M],
        _ inherited: (@Sendable (String) throws -> M)?,
        _ kind: String
    ) -> (@Sendable (String) throws -> M)? where M: Sendable {
        if aliases.isEmpty { return inherited }
        return { id in
            if let model = aliases[id] { return model }
            if let inherited { return try inherited(id) }
            throw AIError.invalidRequest("No \(kind) model \"\(id)\" in custom provider")
        }
    }
    return ProviderRegistry.Provider(
        languageModel: compose(languageModels, fallback?.languageModel, "language"),
        embeddingModel: compose(embeddingModels, fallback?.embeddingModel, "embedding"),
        imageModel: compose(imageModels, fallback?.imageModel, "image"),
        speechModel: compose(speechModels, fallback?.speechModel, "speech"),
        transcriptionModel: compose(transcriptionModels, fallback?.transcriptionModel, "transcription"),
        rerankingModel: compose(rerankingModels, fallback?.rerankingModel, "reranking")
    )
}
