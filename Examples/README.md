# Examples

Each file is one feature, in reading order. The whole folder is compiled as a
target on every `swift build`, so the examples can never drift from the API.

| File | Shows |
|---|---|
| [01-GenerateText.swift](01-GenerateText.swift) | One-shot generation with `system` + `prompt` |
| [02-StreamText.swift](02-StreamText.swift) | Token streaming via `textStream`, loop events via `fullStream` |
| [03-OnDeviceOrCloud.swift](03-OnDeviceOrCloud.swift) | The wedge: Foundation Models with one-line cloud fallback |
| [04-ProviderSwap.swift](04-ProviderSwap.swift) | 14 providers behind one `LanguageModel`, plus custom gateways |
| [05-Tools.swift](05-Tools.swift) | Tool calling, the agentic loop, `stopWhen`, typed args, `prepareStep` |
| [06-GenerateObject.swift](06-GenerateObject.swift) | Structured output into a `Decodable` |
| [07-StreamObject.swift](07-StreamObject.swift) | Streaming partial objects |
| [08-Embeddings.swift](08-Embeddings.swift) | `embed` / `embedMany` / `cosineSimilarity`, tiny semantic search |
| [09-ChatSession.swift](09-ChatSession.swift) | `ChatSession` against a remote AI SDK route and a local model |
| [10-Agent.swift](10-Agent.swift) | `Agent` (ToolLoopAgent analog), also usable as a `ChatTransport` |
| [11-Middleware.swift](11-Middleware.swift) | `wrapLanguageModel`, extractReasoning, defaultSettings |
| [12-ImageGeneration.swift](12-ImageGeneration.swift) | `generateImage` |
| [13-SpeechAndTranscription.swift](13-SpeechAndTranscription.swift) | `generateSpeech` and `transcribe` |
| [14-VideoGeneration.swift](14-VideoGeneration.swift) | `generateVideo`, text-to-video and image-to-video |
| [15-Rerank.swift](15-Rerank.swift) | `rerank` with Cohere |
| [16-ToolApprovals.swift](16-ToolApprovals.swift) | `needsApproval`, client-side tools, `addToolResult` |
| [17-MultimodalAndSettings.swift](17-MultimodalAndSettings.swift) | Vision input, `toolChoice`, sampling settings, `reasoning`, callbacks |
| [18-Schema.swift](18-Schema.swift) | `Schema` DSL (the zod analog): combinators, validation, typed tools |
| [19-SessionHooks.swift](19-SessionHooks.swift) | `CompletionSession` and `ObjectSession` (the hook family) |
| [20-SubagentsAndContext.swift](20-SubagentsAndContext.swift) | `Agent.asTool` subagents, `toolsContext`, `customProvider` |
| [21-UIStreamsAndTesting.swift](21-UIStreamsAndTesting.swift) | `UIMessageStream.build`, `readUIMessageStream`, metadata, `AITesting` |
| [22-Realtime.swift](22-Realtime.swift) | `RealtimeSession` voice conversations across OpenAI, Google, xAI |

API keys are read from the environment in [Support.swift](Support.swift)
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GROQ_API_KEY`).
