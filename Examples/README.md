# Examples

The examples are organized in two ways:

- [`Providers/`](Providers/) contains provider-specific examples split by capability.
- [`Features/`](Features/) contains provider-neutral tutorials in reading order.

The complete tree is compiled by the `Examples` SwiftPM target on every build,
so examples are checked against the public API:

```sh
swift build --target Examples
```

These files are small, copyable functions rather than separate executables. Copy
the function you need into an app or command-line target, supply the provider's
API key, and call it from an async context. Examples that read local media use
obvious temporary paths such as `/tmp/example.png` and `/tmp/audio.mp3`; replace
them with files available to your app.

## Provider examples

| Provider | Capabilities shown |
|---|---|
| [AI Gateway](Providers/AIGateway/) | Text and streaming; tools, structured output, and vision |
| [Amazon Bedrock](Providers/AmazonBedrock/) | Text and reasoning; tools, structured output, and vision |
| [Anthropic](Providers/Anthropic/) | Text and reasoning; client and server tools; structured output; images, PDFs, files, and skills |
| [Apple Foundation Models](Providers/AppleFoundationModels/) | On-device text and streaming; tools; structured output; chat and cloud fallback; Private Cloud Compute |
| [AssemblyAI](Providers/AssemblyAI/) | Transcription |
| [Azure OpenAI](Providers/AzureOpenAI/) | Text, streaming, tools, structured output, vision, reasoning, and embeddings |
| [Baseten](Providers/Baseten/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Cerebras](Providers/Cerebras/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Cohere](Providers/Cohere/) | Text, streaming, citations, tools, structured output, vision, embeddings, and reranking |
| [DeepInfra](Providers/DeepInfra/) | Text and streaming; tools, structured output, vision, and reasoning |
| [DeepSeek](Providers/DeepSeek/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Deepgram](Providers/Deepgram/) | Speech generation and transcription |
| [ElevenLabs](Providers/ElevenLabs/) | Speech generation and transcription |
| [Fireworks](Providers/Fireworks/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Gladia](Providers/Gladia/) | Transcription |
| [Google](Providers/Google/) | Text and reasoning; tools and grounding; structured output; vision and files; Vertex AI; realtime |
| [Groq](Providers/Groq/) | Text and reasoning; tools, structured output, vision, and transcription |
| [Hume](Providers/Hume/) | Speech generation |
| [LMNT](Providers/LMNT/) | Speech generation |
| [LM Studio](Providers/LMStudio/) | Local text and streaming; tools, structured output, vision, and reasoning |
| [Luma](Providers/Luma/) | Image and video generation |
| [Mistral](Providers/Mistral/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Ollama](Providers/Ollama/) | Local text and streaming; reasoning and tools |
| [OpenAI](Providers/OpenAI/) | Responses and Chat Completions; reasoning; tools; structured output; vision; embeddings; images; speech; transcription; realtime; files |
| [OpenAI-compatible](Providers/OpenAICompatible/) | Custom OpenAI-compatible text and embedding endpoints |
| [OpenRouter](Providers/OpenRouter/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Perplexity](Providers/Perplexity/) | Search, citations, reasoning, structured output, and vision |
| [Replicate](Providers/Replicate/) | Image generation |
| [Rev.ai](Providers/RevAI/) | Transcription |
| [Sarvam](Providers/Sarvam/) | Text and reasoning, speech generation, and transcription |
| [Together AI](Providers/TogetherAI/) | Text and streaming; tools, structured output, vision, and reasoning |
| [Vercel](Providers/Vercel/) | Text and vision through an AI SDK route |
| [fal](Providers/fal/) | Image generation |
| [xAI](Providers/xAI/) | Text and reasoning; search and server tools; structured output and vision; video; realtime |

## Feature tutorials

| File | Shows |
|---|---|
| [01-GenerateText.swift](Features/01-GenerateText.swift) | One-shot generation with `system` and `prompt` |
| [02-StreamText.swift](Features/02-StreamText.swift) | Token streaming through `textStream` and loop events through `fullStream` |
| [03-OnDeviceOrCloud.swift](Features/03-OnDeviceOrCloud.swift) | Foundation Models with a one-line cloud fallback |
| [04-ProviderSwap.swift](Features/04-ProviderSwap.swift) | Multiple providers behind one `LanguageModel`, plus custom gateways |
| [05-Tools.swift](Features/05-Tools.swift) | Tool calling, the agentic loop, `stopWhen`, typed arguments, and `prepareStep` |
| [06-GenerateObject.swift](Features/06-GenerateObject.swift) | Structured output decoded into a Swift type |
| [07-StreamObject.swift](Features/07-StreamObject.swift) | Streaming partial objects |
| [08-Embeddings.swift](Features/08-Embeddings.swift) | `embed`, `embedMany`, cosine similarity, and semantic search |
| [09-ChatSession.swift](Features/09-ChatSession.swift) | `ChatSession` against a remote AI SDK route and a local model |
| [10-Agent.swift](Features/10-Agent.swift) | `Agent`, including use as a `ChatTransport` |
| [11-Middleware.swift](Features/11-Middleware.swift) | `wrapLanguageModel`, reasoning extraction, and default settings |
| [12-ImageGeneration.swift](Features/12-ImageGeneration.swift) | Image generation |
| [13-SpeechAndTranscription.swift](Features/13-SpeechAndTranscription.swift) | Speech generation and transcription |
| [14-VideoGeneration.swift](Features/14-VideoGeneration.swift) | Text-to-video and image-to-video generation |
| [15-Rerank.swift](Features/15-Rerank.swift) | Reranking with Cohere |
| [16-ToolApprovals.swift](Features/16-ToolApprovals.swift) | Tool approval, client-side tools, and `addToolResult` |
| [17-MultimodalAndSettings.swift](Features/17-MultimodalAndSettings.swift) | Vision input, tool choice, sampling settings, reasoning, and callbacks |
| [18-Schema.swift](Features/18-Schema.swift) | Schema combinators, validation, and typed tools |
| [19-SessionHooks.swift](Features/19-SessionHooks.swift) | `CompletionSession` and `ObjectSession` |
| [20-SubagentsAndContext.swift](Features/20-SubagentsAndContext.swift) | Subagents, tool context, and custom providers |
| [21-UIStreamsAndTesting.swift](Features/21-UIStreamsAndTesting.swift) | UI message streams, metadata, and `AITesting` |
| [22-Realtime.swift](Features/22-Realtime.swift) | Realtime voice sessions across OpenAI, Google, and xAI |
| [23-WorkflowGuides.swift](Features/23-WorkflowGuides.swift) | Complete workflows used by the semantic search, transcription, media, gateway, reliability, and server-tool guides |

Shared helpers and the small set of environment-backed keys used by the feature
tutorials live in [Support.swift](Support.swift). Provider examples keep their
own credentials close to the model construction so each file remains copyable.
