# Reasoning

One portable `reasoning` parameter controls a model's internal thinking phase across every provider. It is available on `generateText`, `streamText`, and `Agent`, and defaults to `.providerDefault`.

## ReasoningEffort

```swift
public enum ReasoningEffort: String, Sendable, Codable {
    case providerDefault = "provider-default"
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    public var isCustom: Bool { self != .providerDefault }
    public func budget(maxOutputTokens: Int, maxBudget: Int, minBudget: Int = 1024) -> Int?
}
```

- `.providerDefault` — the default; behaves as if the parameter was omitted (no reasoning fields sent).
- `.none` — explicitly disables thinking where the provider allows it.
- `.minimal .low .medium .high .xhigh` — increasing effort.

```swift
import AI

let result = try await generateText(
    model: AnthropicModel("claude-sonnet-5"),
    prompt: "How many people will live in the world in 2040?",
    reasoning: .medium
)
print(result.reasoningText)   // the thinking
print(result.text)            // the answer
```

Passing it is identical on `streamText` and `Agent`:

```swift
let stream = streamText(model: model, prompt: prompt, reasoning: .high)

let agent = Agent(model: model, instructions: "Be rigorous.", reasoning: .high)
```

## Consuming reasoning output

After a non-streaming call, read `result.reasoningText` (last step) or `step.reasoningText` per step. While streaming, thinking arrives as its own delta on `fullStream`:

```swift
for try await part in stream.fullStream {
    switch part {
    case .reasoningDelta(let thought): renderThinking(thought)
    case .textDelta(let text):         renderAnswer(text)
    default:                           break
    }
}
```

Thinking-token accounting shows up in `result.usage.reasoningTokens` where the provider reports it.

## Budgets

Budget-based wires get a token count from `ReasoningEffort.budget(maxOutputTokens:maxBudget:minBudget:)`. The fractions are `.minimal` 2%, `.low` 10%, `.medium` 30%, `.high` 60%, `.xhigh` 90%, clamped to `[minBudget, maxBudget]` (minBudget defaults to 1024). `.none` and `.providerDefault` return `nil`.

```swift
ReasoningEffort.medium.budget(maxOutputTokens: 64_000, maxBudget: 64_000)   // 19200
```

## Per-provider translation

`isCustom` gates everything: `.providerDefault` sends nothing. Otherwise each provider maps the effort to its native field — an effort enum where one exists, a computed token budget where it does not.

| Provider | Wire translation |
| --- | --- |
| OpenAI (Responses) | `reasoning.effort` + an automatic detailed summary |
| OpenAI (chat) | `reasoning_effort`, passed verbatim |
| Anthropic | Adaptive models: `thinking.type: "adaptive"` + `output_config.effort`. Older models: `thinking.type: "enabled"` with a computed `budget_tokens`, raising `max_tokens` to fit. `.none` → `thinking.type: "disabled"` |
| Google | Gemini 3: `thinkingLevel`. Gemini 2.5: `thinkingBudget` (0 for `.none`) |
| Bedrock | By model family: Claude thinking config (adaptive/budget), OpenAI `reasoning_effort`, or a generic `reasoningConfig.maxReasoningEffort` |
| xAI | `reasoning.effort` (`minimal`→low, `xhigh`→high) |
| Groq | `reasoning_effort` (`xhigh`→high) |
| DeepSeek | `thinking.type` + `reasoning_effort` (`xhigh`→max) |
| Fireworks | `reasoning_effort` coerced to three levels |
| Mistral | `reasoning_effort`, reasoning models only |
| Perplexity, Cohere | no reasoning knob; value ignored |

### Anthropic, precisely

- **Adaptive models** (Sonnet 5, Fable 5, Opus 4.7/4.8, the 4.6 pair) get `thinking.type: "adaptive"` plus `output_config.effort`. `.minimal` coerces to `low`; `.xhigh` stays `xhigh` where supported and becomes `max` on 4.6-generation models.
- **Older models** get `thinking.type: "enabled"` with `budget_tokens` computed against that model's real output ceiling (64k for the 4.5 family and Sonnet 4, 32k for Opus 4/4.1), and `max_tokens` is raised when the budget would not otherwise fit.
- `.none` sends `thinking.type: "disabled"`.

### Google, precisely

Gemini 3 takes `thinkingLevel` (`.none` and `.minimal` map to `minimal` — thinking can't be fully disabled there; `.xhigh` caps at `high`). Everything else takes a `thinkingBudget`: `0` for `.none`, otherwise a fraction of the 65,536-token ceiling capped at 32,768 for 2.5 Pro and 24,576 for the rest.

## Precedence

Reasoning settings inside `providerOptions` always win, and the two are never merged. Use the portable parameter by default; drop to `providerOptions` when you need an exact budget.

```swift
let result = try await generateText(
    model: AnthropicModel("claude-sonnet-4-5"),
    prompt: prompt,
    reasoning: .low,   // ignored: the explicit budget below wins
    providerOptions: [
        "thinking": ["type": "enabled", "budget_tokens": 12000]
    ]
)
```

## Extracting inline `<think>` blocks

Some open models (on Ollama or Groq) emit thinking inline rather than as structured deltas. Wrap the model in the extract-reasoning middleware to split it out:

```swift
let model = wrapLanguageModel(
    model: OpenAICompatibleProvider.ollama()("deepseek-r1"),
    middleware: [.extractReasoning(tag: "think")]
)
```

## Gotchas

- `reasoning` is a non-optional enum. `.providerDefault` (not `.none`) means "leave it to the provider"; `.none` actively disables thinking. This is deliberate — an optional `.none` would collide with `Optional.none`.
- Providers without a reasoning knob (Perplexity, Cohere) silently ignore the value.
- `providerOptions` reasoning fields override the `reasoning` parameter entirely; do not expect them to combine.
- Effort levels are coerced per provider (e.g. `.xhigh`→high on xAI/Groq, →max on DeepSeek), so the same enum yields different wire values across providers.
