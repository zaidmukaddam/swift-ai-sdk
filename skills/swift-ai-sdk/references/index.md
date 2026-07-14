# References — router

Pick the file that matches the task. Open one or two, not all.

| File | Use for |
| --- | --- |
| [text-generation.md](text-generation.md) | `generateText` / `streamText`, prompts and messages, sampling settings, stop conditions, lifecycle callbacks, sources/citations |
| [structured-output.md](structured-output.md) | `generateObject`, `streamObject` (+ `elementStream`), `generateEnum`, `generateJSON`, and the `Schema` DSL |
| [tools.md](tools.md) | Function `Tool`, typed arguments, execution context, human-in-the-loop approvals, client-side tools, and provider-executed tools (`<Model>.Tools`) |
| [agents.md](agents.md) | `Agent` (the ToolLoopAgent analog), loop control (`stopWhen`/`stepCountIs`/`hasToolCall`), `prepareCall`, `prepareStep`, `toolOrder`, subagents via `asTool` |
| [providers.md](providers.md) | The capability matrix, first-class provider models, custom compatible endpoints, keys/base URLs, `ProviderRegistry`, and `customProvider` |
| [reasoning.md](reasoning.md) | `ReasoningEffort` and how it maps to each provider's native reasoning controls; consuming `.reasoningDelta` |
| [middleware.md](middleware.md) | `wrapLanguageModel` with `cache`, `extractReasoning`, `simulateStreaming`, `defaultSettings`, and custom `wrapCall`/`transformRequest`/`wrapStream` hooks |
| [chat-ui.md](chat-ui.md) | `ChatSession`, `CompletionSession`, `ObjectSession` for SwiftUI; `ChatTransport`/`HTTPChatTransport`/`LocalChatTransport`; the UI-message stream protocol and `/api/chat` compatibility |
| [realtime.md](realtime.md) | `RealtimeSession` and the realtime models (OpenAI, Google Gemini Live, xAI) for live voice |
| [media.md](media.md) | `generateImage`, `generateSpeech`, `transcribe`, `generateVideo` and their provider packs |
| [on-device.md](on-device.md) | `FoundationModelsModel` — Apple Intelligence with a cloud fallback |
| [embeddings.md](embeddings.md) | `embed`, `embedMany`, `cosineSimilarity`, and `rerank` |
| [testing.md](testing.md) | The `AITesting` module, mock models, and `simulateReadableStream` |
| [errors.md](errors.md) | `AIError` cases and handling patterns |
