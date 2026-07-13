---
name: swift-ai-sdk
description: >
  Build AI features in Swift for iOS and macOS with swift-ai-sdk — streaming text,
  structured output, tools, agents, embeddings, speech, transcription, images, video,
  realtime voice, and Apple's on-device models, across every provider (OpenAI, Anthropic,
  Google, xAI, Bedrock, Groq, Mistral, DeepSeek, Perplexity, Cohere, Sarvam, Ollama). Use
  when writing Swift that calls generateText / streamText / generateObject, builds an Agent
  or tool loop, wires a ChatSession into SwiftUI, or adds realtime voice. Activate for
  swift-ai-sdk work even when it isn't named.
---

# swift-ai-sdk

AI features for iOS and macOS apps, in plain Swift. One API across every provider; swap the
model and nothing else in your code moves.

## Install

```swift
// Package.swift
.package(url: "https://github.com/zaidmukaddam/swift-ai-sdk.git", from: "0.1.0")
```

Add `"AI"` to your target's dependencies (and `"AITesting"` to test targets). Requires
Swift 6 / Xcode 16+. `import AI` where you use it. The Foundation Models (on-device)
provider activates automatically when built against the iOS 26 / macOS 26 SDK.

## The one thing to know

Every provider implements `LanguageModel`, and the top-level functions take any
`LanguageModel` — so switching providers is a one-line change:

```swift
let result = try await generateText(
  model: AnthropicModel("claude-sonnet-5"),   // or OpenAIModel(...), GoogleModel(...), XaiModel(...)
  prompt: "Why is the sky blue?"
)
print(result.text)
```

Keys come from the provider's conventional environment variable (`ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `XAI_API_KEY`, …) or an explicit `apiKey:` argument.

## Entry points

| You want | Call |
| --- | --- |
| A whole answer | `generateText` |
| Token streaming | `streamText().textStream` |
| Typed JSON / enum | `generateObject` / `streamObject` / `generateEnum` |
| A reusable agent | `Agent` |
| Embeddings / rerank | `embed`, `embedMany` / `rerank` |
| Speech, transcription, images, video | `generateSpeech`, `transcribe`, `generateImage`, `generateVideo` |
| A SwiftUI chat | `ChatSession` |
| Realtime voice | `RealtimeSession` |

## References

Open only what the task needs. **Start at `references/index.md`** — a router table mapping
topic → file with a one-line "use for" per file. Then read only the `references/<name>.md`
files you need; don't read them all.

| Topic | File |
| --- | --- |
| Text generation, settings, callbacks | `references/text-generation.md` |
| Structured output + the Schema DSL | `references/structured-output.md` |
| Tools: function, typed, approvals, provider-executed | `references/tools.md` |
| Agents, loop control, prepareCall/prepareStep/toolOrder | `references/agents.md` |
| Providers: matrix, construction, provider tools, Sarvam | `references/providers.md` |
| Reasoning effort per provider | `references/reasoning.md` |
| Middleware: cache, extractReasoning, defaultSettings | `references/middleware.md` |
| Chat UI: ChatSession, transport, stream protocol | `references/chat-ui.md` |
| Realtime voice | `references/realtime.md` |
| Media: image, speech, transcription, video | `references/media.md` |
| On-device (Apple Intelligence) | `references/on-device.md` |
| Embeddings & reranking | `references/embeddings.md` |
| Testing & mocks | `references/testing.md` |
| Errors | `references/errors.md` |

## Conventions

- Async throughout: `try await` for one-shots, `for try await part in stream` for streams.
- Message roles: `.system`, `.user`, `.assistant`, `.tool`. Build a prompt with `system:` +
  `prompt:`, or pass `messages: [Message]` directly.
- The full docs mirror this skill at https://swift-ai-sdk.dev/docs — every page is also raw
  markdown (append `.mdx` to any URL, or start at `/llms.txt`).
