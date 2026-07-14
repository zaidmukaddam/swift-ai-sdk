import AI
import Foundation

// MARK: - Semantic search

struct WorkflowPassage: Sendable {
    let text: String
    let embedding: [Double]
}

func workflowBuildIndex(_ passages: [String]) async throws -> [WorkflowPassage] {
    let result = try await embedMany(
        model: OpenAIEmbeddingModel("text-embedding-3-small"),
        values: passages,
        maxBatchSize: 96
    )
    return zip(passages, result.embeddings).map(WorkflowPassage.init)
}

func workflowAnswerFromIndex(
    question: String,
    index: [WorkflowPassage]
) async throws -> String {
    let query = try await embed(
        model: OpenAIEmbeddingModel("text-embedding-3-small"),
        value: question
    )
    let candidates = index
        .map { ($0.text, cosineSimilarity(query.embedding, $0.embedding)) }
        .sorted { $0.1 > $1.1 }
        .prefix(8)
        .map(\.0)

    guard !candidates.isEmpty else { return "No relevant context found." }
    let reranked = try await rerank(
        model: CohereRerankingModel("rerank-v4-fast"),
        query: question,
        documents: candidates,
        topN: 3
    )
    let context = reranked.rankedDocuments.map(\.document).joined(separator: "\n\n")
    return try await generateText(
        model: OpenAIModel("gpt-5.6-sol"),
        system: "Answer only from the supplied context. Say when the answer is absent.",
        prompt: "Context:\n\(context)\n\nQuestion: \(question)"
    ).text
}

// MARK: - Transcribe and summarize

struct WorkflowMeetingNotes: Codable, Sendable {
    let title: String
    let summary: String
    let actionItems: [String]
}

let workflowMeetingNotesSchema: JSONValue = [
    "type": "object",
    "properties": [
        "title": ["type": "string"],
        "summary": ["type": "string"],
        "actionItems": ["type": "array", "items": ["type": "string"]]
    ],
    "required": ["title", "summary", "actionItems"],
    "additionalProperties": false
]

func workflowTranscribeAndSummarize(audioURL: URL) async throws -> WorkflowMeetingNotes {
    let transcript = try await transcribe(
        model: OpenAITranscriptionModel("whisper-1"),
        audio: Data(contentsOf: audioURL),
        mediaType: "audio/mpeg"
    )
    return try await generateObject(
        model: OpenAIModel("gpt-5.6-sol"),
        of: WorkflowMeetingNotes.self,
        schema: workflowMeetingNotesSchema,
        schemaName: "meeting_notes",
        prompt: "Summarize this transcript and extract action items:\n\n\(transcript.text)"
    ).object
}

// MARK: - Image and video generation

func workflowGenerateImageAndVideo(outputDirectory: URL) async throws -> GenerateVideoResult {
    let image = try await generateImage(
        model: OpenAIImageModel("gpt-image-2"),
        prompt: "A paper boat drifting down a rainy street, cinematic",
        size: "1024x1024"
    )
    let imageURL = outputDirectory.appendingPathComponent("paper-boat.png")
    try image.image.write(to: imageURL)

    return try await generateVideo(
        model: XaiVideoModel("grok-imagine-video-1.5"),
        prompt: "The boat drifts forward while rain ripples across the street",
        image: ImageContent(data: image.image, mediaType: "image/png"),
        aspectRatio: "16:9",
        duration: 6
    )
}

// MARK: - Custom endpoints

func workflowCustomGateway() -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(
        name: "company-gateway",
        baseURL: URL(string: "https://llm.example.com/v1")!,
        apiKey: ProcessInfo.processInfo.environment["GATEWAY_API_KEY"],
        headers: ["x-team": "ios"],
        queryParams: ["api-version": "2026-01-01"]
    )
}

func workflowAskCustomGateway() async throws -> String {
    let gateway = workflowCustomGateway()
    return try await generateText(
        model: gateway("openai/gpt-oss-20b"),
        prompt: "Explain Swift actors in three sentences."
    ).text
}

// MARK: - Production reliability

struct WorkflowTelemetryCollector: AITelemetryCollector {
    func record(_ event: AITelemetryEvent) {
        print(event.name, event.phase.rawValue, event.duration)
    }
}

func workflowIsTransient(_ error: Error) -> Bool {
    switch error {
    case AIError.http(let status, _):
        return status == 408 || status == 409 || status == 429 || (500..<600).contains(status)
    case AIError.transport:
        return true
    case is URLError:
        return true
    default:
        return false
    }
}

func workflowReliableAnswer(_ prompt: String) async throws -> String {
    AITelemetry.collector = WorkflowTelemetryCollector()
    let primary = wrapLanguageModel(
        model: OpenAIModel("gpt-5.6-sol"),
        middleware: [.cache(), .defaultSettings(temperature: 0.2)]
    )
    do {
        return try await generateText(
            model: primary,
            prompt: prompt,
            maxRetries: 4
        ).text
    } catch where workflowIsTransient(error) {
        return try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: prompt,
            maxRetries: 2
        ).text
    }
}

// MARK: - Search and server tools

func workflowResearchWithServerTools(_ question: String) async throws -> GenerateTextResult {
    let tools: [any AIToolProtocol] = [
        exampleWeatherTool(),
        OpenAIModel.Tools.webSearch(allowedDomains: ["swift.org"]),
        OpenAIModel.Tools.codeInterpreter()
    ]
    return try await generateText(
        model: OpenAIModel("gpt-5.6-sol"),
        prompt: question,
        tools: tools,
        stopWhen: [stepCountIs(6)]
    )
}
