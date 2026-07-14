# Providers

Every provider is a `LanguageModel` (or `EmbeddingModel` / `SpeechModel` / `TranscriptionModel` / `RerankingModel`). Construct a pack, pass it to `generateText` / `streamText` / `generateObject` / `embed`. All packs read their key from an env var when `apiKey:` is omitted, and expose `baseURL:`, `headers:`, and `urlSession:` overrides. `import AI`.

## Capability matrix (language models)

| Provider | Tools | Structured output | Reasoning | Vision | Sources | Cached tokens |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| OpenAI (Responses) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| OpenAI (chat) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Azure OpenAI | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Anthropic | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Google / Vertex | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Bedrock | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| xAI | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Groq | ✓* | ✓* | ✓ | ✓* | — | ✓ |
| DeepSeek | ✓* | ✓* | ✓ | ✓* | — | ✓ |
| Mistral | ✓* | ✓* | ✓ | ✓* | — | — |
| Perplexity | — | ✓* | — | ✓* | ✓ | — |
| Cohere | ✓ | ✓ | — | ✓ | ✓ | — |
| Foundation Models | ✓ | ✓ | — | — | — | — |
| OpenAI-compatible | ✓* | ✓* | ✓* | ✓* | — | — |

`*` rides the shared chat-completions wire; honored only if the model supports it. Sources surface as `StreamPart.source` / `TextStreamPart.source`. Cached tokens populate `usage.cachedInputTokens` on prompt-cache hits.

Model ids are free strings — anything the provider's API serves works. The ids below are illustrative.

## Native packs

Each ctor is `init(_ modelID: String, apiKey: String? = nil, baseURL:..., headers: [String:String] = [:], urlSession: URLSession = .shared)` unless noted. `apiKey: nil` falls back to the env var.

### OpenAI — `OpenAIModel` (Responses API by default) / `.chat` (Chat Completions)

Env `OPENAI_API_KEY`, base `https://api.openai.com/v1`.

```swift
let m = OpenAIModel("gpt-5.1")
let chat = OpenAIModel.chat("gpt-4o")
```

`init(_:apiKey:baseURL:organization:project:headers:urlSession:)` — `baseURL` is `URL?` (nil → default). `organization` / `project` become headers. `.chat(_:...)` is a static returning an `OpenAIModel` backed by the Chat Completions engine (`OpenAIChatModel`). Reasoning ruleset applies to `o1*`, `o3*`, `o4-mini*`, `gpt-5*` except `gpt-5-chat*`; `gpt-5.1`–`gpt-5.6` re-accept `temperature`/`topP` when reasoning effort is `none`.

### Anthropic — `AnthropicModel`

Env `ANTHROPIC_API_KEY`, base `https://api.anthropic.com/v1`. Extra arg `anthropicVersion: String = "2023-06-01"`.

```swift
let m = AnthropicModel("claude-sonnet-5")
```

Reasoning translates to adaptive thinking / `budget_tokens` by model family; output ceilings 4,096 → 128k. Same table drives Bedrock `anthropic.*` ids.

### Google — `GoogleModel`

Env `GOOGLE_GENERATIVE_AI_API_KEY`, base `https://generativelanguage.googleapis.com/v1beta`.

```swift
let m = GoogleModel("gemini-3-pro")
```

`gemini-3*` takes `thinkingLevel`; other budget models cap thinking tokens (32,768 for 2.5 Pro / `gemini-3-pro-image`, 24,576 otherwise). Reasoning surfaces as `.reasoningDelta`.

### Google Vertex — `GoogleVertexModel`

`init(_ modelID:project:location:apiKey:accessToken:baseURL:headers:urlSession:)`. `provider == "google.vertex"`. Env `GOOGLE_VERTEX_PROJECT`, `GOOGLE_VERTEX_LOCATION` (default `global`), `GOOGLE_VERTEX_API_KEY`. Auth precedence: `apiKey`/env → `x-goog-api-key`; else `accessToken` → bearer; else none. `baseURL` is `URL?`.

```swift
let m = GoogleVertexModel("gemini-3-pro", project: "my-proj", location: "us-central1")
```

### Azure OpenAI — `AzureOpenAIProvider` (factory, not a model)

A provider object you call to mint deployment-backed models. `init(resourceName:apiKey:baseURL:apiVersion:useDeploymentBasedUrls:headers:urlSession:)`. Env `AZURE_RESOURCE_NAME`, `AZURE_API_KEY`. Default URL `https://{resource}.openai.azure.com/openai`.

```swift
let azure = AzureOpenAIProvider(resourceName: "my-resource")
let m = azure("my-gpt-5-deployment")
let emb = azure.textEmbeddingModel("my-embed-deployment")
```

`callAsFunction` == `languageModel(_:)` → `OpenAIChatModel`. Also `textEmbeddingModel(_:)`.

### Bedrock — `BedrockModel`

`init(_ modelID:apiKey:region:baseURL:headers:urlSession:)`. Env `AWS_BEARER_TOKEN_BEDROCK`. `region: String = "us-east-1"`, default base `https://bedrock-runtime.{region}.amazonaws.com`. Reasoning by id prefix: `anthropic.*` → Claude thinking, `openai.*` → `reasoning_effort`, else generic `reasoningConfig` (`xhigh` → `max`).

```swift
let m = BedrockModel("anthropic.claude-sonnet-5", region: "us-west-2")
```

### xAI — `XaiModel` (Responses) / `.chat`

Env `XAI_API_KEY`, base `https://api.x.ai/v1`. Same `OpenAIModel`-style split. Has `SearchParameters` for live search (sources).

```swift
let m = XaiModel("grok-4.20")
let chat = XaiModel.chat("grok-4.20")
```

`grok-4.20` date-stamped `-reasoning`/`-non-reasoning` variants ignore the `reasoning` param (behavior baked in).

### Groq / DeepSeek / Mistral / Perplexity — chat-completions wrappers

All wrap `OpenAIChatModel`; `init(_ modelID:apiKey:baseURL:headers:urlSession:)`.

| Pack | Env | Base URL |
| --- | --- | --- |
| `GroqModel` | `GROQ_API_KEY` | `https://api.groq.com/openai/v1` |
| `DeepSeekModel` | `DEEPSEEK_API_KEY` | `https://api.deepseek.com` |
| `MistralModel` | `MISTRAL_API_KEY` | `https://api.mistral.ai/v1` |
| `PerplexityModel` | `PERPLEXITY_API_KEY` | `https://api.perplexity.ai` |

```swift
let g = GroqModel("llama-3.3-70b-versatile")
let d = DeepSeekModel("deepseek-reasoner")
let p = PerplexityModel("sonar-pro")
```

Mistral maps `reasoning` → `reasoning_effort` only on `mistral-small-latest`, `mistral-small-2603`, `mistral-medium-3`, `mistral-medium-3.5`. Perplexity has no upstream tool calling; sources surface as citations.

### Cohere — `CohereModel`

Env `COHERE_API_KEY`, base `https://api.cohere.com/v2`. Companion `CohereEmbeddingModel` (same env/base) and `CohereRerankingModel`. Citations surface as sources.

```swift
let m = CohereModel("command-a")
```

## First-class models on compatible endpoints

Named services have dedicated `LanguageModel` types even when they share the chat-completions wire:

| Model | Endpoint | Key from |
| --- | --- | --- |
| `TogetherAIModel` | `api.together.xyz/v1` | `TOGETHER_API_KEY` |
| `FireworksModel` | `api.fireworks.ai/inference/v1` | `FIREWORKS_API_KEY` |
| `CerebrasModel` | `api.cerebras.ai/v1` | `CEREBRAS_API_KEY` |
| `OpenRouterModel` | `openrouter.ai/api/v1` | `OPENROUTER_API_KEY` |
| `DeepInfraModel` | `api.deepinfra.com/v1/openai` | `DEEPINFRA_API_KEY` |
| `BasetenModel` | `inference.baseten.co/v1` | `BASETEN_API_KEY` |
| `VercelModel` | `api.v0.dev/v1` | `V0_API_KEY` |
| `AIGatewayModel` | `ai-gateway.vercel.sh/v1` | `AI_GATEWAY_API_KEY` |
| `SarvamModel` | `api.sarvam.ai/v1` | `SARVAM_API_KEY` |
| `OllamaModel` | `localhost:11434/v1` | no key |
| `LMStudioModel` | `localhost:1234/v1` | no key |

Each initializer is `init(_ modelID:apiKey:baseURL:headers:urlSession:)`; `baseURL: nil` selects the provider default.

```swift
let hosted = TogetherAIModel("MiniMaxAI/MiniMax-M3")
let local = OllamaModel("gemma4")
```

## Custom compatible endpoints — `OpenAICompatibleProvider`

Provider object for a custom chat-completions endpoint. `callAsFunction(_:)` == `languageModel(_:)` → `OpenAIChatModel`; also `textEmbeddingModel(_:)`. General init:

```swift
let p = OpenAICompatibleProvider(
  name: "myhost",
  baseURL: URL(string: "https://api.example.com/v1")!,
  apiKey: "sk-...",
  headers: [:], queryParams: [:]
)
let m = p("openai/gpt-oss-20b")
```

The old named factory methods remain deprecated for source compatibility. New code should use the first-class model types.

## Sarvam trio (Indic)

One key `SARVAM_API_KEY` across all three surfaces.

- Chat: `SarvamModel("sarvam-105b")`. `sarvam-30b` (64K) / `sarvam-105b` (128K) are reasoning models; `reasoning` → `reasoning_effort`, thinking streams back as `.reasoningDelta`.
- TTS: `SarvamSpeechModel(_ modelID: String = "bulbul:v3", apiKey:targetLanguage: String = "en-IN", baseURL:headers:urlSession:)`, base `https://api.sarvam.ai`. Language override + Sarvam knobs (`pitch`, `loudness`, `temperature`, `speech_sample_rate`) via `providerOptions`.
- STT: `SarvamTranscriptionModel(_ modelID: String = "saaras:v3", apiKey:baseURL:headers:urlSession:)`. `language_code`/`mode` via `providerOptions`; `mode` ∈ `transcribe|translate|verbatim|translit|codemix`.

```swift
let tts = SarvamSpeechModel("bulbul:v3", targetLanguage: "hi-IN")
let audio = try await generateSpeech(model: tts, text: "नमस्ते", voice: "anushka", outputFormat: "mp3")

let stt = SarvamTranscriptionModel("saaras:v3")
let r = try await transcribe(model: stt, audio: audioData, mediaType: "audio/wav",
                             providerOptions: ["language_code": "hi-IN", "mode": "transcribe"])
```

## Registry — `provider:model` strings

`ProviderRegistry` resolves `"provider:model"` (separator `:` by default) to a typed model. Build it from `ProviderRegistry.Provider` factories; `customProvider(...)` gives per-id aliases with a `fallback`.

```swift
let registry = ProviderRegistry(providers: [
  "openai": ProviderRegistry.Provider { OpenAIModel($0) },
  "anthropic": customProvider(
    languageModels: ["fast": AnthropicModel("claude-haiku-4.5")],
    fallback: ProviderRegistry.Provider { AnthropicModel($0) }
  )
])

let m = try registry.languageModel("anthropic:fast")
let m2 = try registry.languageModel("openai:gpt-5.1")
```

Lookups: `languageModel`, `embeddingModel`, `imageModel`, `speechModel`, `transcriptionModel`, `rerankingModel` — each throws `AIError.invalidRequest` on a bad id, unknown provider, or a provider that lacks that model kind. `ProviderRegistry.Provider(_:)` has a shorthand init taking just a language-model closure.

## Gotchas

- `apiKey: nil` resolves to the env var and defaults to `""` (empty), not a crash — a missing key surfaces later as `AIError.http(status: 401, ...)`.
- `OpenAIModel` and `XaiModel` default to the **Responses** API; call `.chat(...)` for Chat Completions. `Groq/DeepSeek/Mistral/Perplexity` are always Chat Completions.
- `baseURL` type differs: `URL?` on `OpenAIModel`/`GoogleVertexModel`/`BedrockModel`/`AzureOpenAIProvider` (nil → default), non-optional `URL` with a default on the others.
- `AzureOpenAIProvider` and custom `OpenAICompatibleProvider` values are provider objects, not models — call them (`provider("id")`) to get an `OpenAIChatModel`.
- Vertex `provider` is `"google.vertex"`; if you register it under `"google"` in a `ProviderRegistry`, the `provider:model` prefix and the pack's `provider` string will differ.
- Perplexity: no tool calling upstream; passing `tools:` won't produce tool calls.
- Embeddings only on OpenAI, Azure OpenAI, Cohere, and any OpenAI-compatible endpoint (`textEmbeddingModel`). Reranking only on Cohere.
