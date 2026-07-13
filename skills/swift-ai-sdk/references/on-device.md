# On-device: Apple Foundation Models

`FoundationModelsModel` runs Apple's on-device model (and optionally Private Cloud Compute) through the same `LanguageModel` protocol as every cloud provider — no network, no key, no data leaving the device. `import AI`.

## Availability gating

The type is compiled only when the Foundation Models framework is present, so it lives behind `#if canImport(FoundationModels)` and is `@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`. Build with the iOS 26 / macOS 26 SDK (or newer) to reach it. Availability also depends on the device and Apple Intelligence settings at runtime.

```swift
public static var isAvailable: Bool           // == availability == .available
public static var availability: SystemLanguageModel.Availability
```

`isAvailable` is a static; check it before constructing.

## Construction

```swift
public init(systemModel: SystemLanguageModel = .default)
```

```swift
let local = FoundationModelsModel()
let result = try await generateText(model: local, prompt: "One-line haiku about rain.")
```

`provider == "apple"`, `modelID == "foundation-models"`.

## Cloud fallback

Pick on-device when available, fall back to any cloud model in one line. Both branches type as `any LanguageModel`, and everything downstream (tools, streaming, structured output, chat) is identical.

```swift
let model: any LanguageModel = FoundationModelsModel.isAvailable
  ? FoundationModelsModel()
  : AnthropicModel("claude-sonnet-5")
```

There is also a convenience static that does the same branch:

```swift
public static func orFallback(_ fallback: any LanguageModel) -> any LanguageModel
// let model = FoundationModelsModel.orFallback(AnthropicModel("claude-sonnet-5"))
```

## Private Cloud Compute

PCC support is compiled only under `#if compiler(>=6.4)` and gated `@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)`:

```swift
public init(privateCloudCompute model: PrivateCloudComputeLanguageModel)
public static func privateCloudCompute() -> FoundationModelsModel
// let pcc = FoundationModelsModel.privateCloudCompute()
```

PCC requires the `com.apple.developer.private-cloud-compute` entitlement. Without it the system call traps (crashes) rather than throwing, so gate PCC builds to provisioned targets only. `modelID` for the PCC instance is `foundation-models-pcc`. Quota-exhaustion arrives as `AIError.transport` mentioning the daily quota.

## What works

- `generateText` / `streamText`, including multi-turn history — the pack rebuilds a Foundation Models `Transcript` from `request.messages` each call (system messages become instructions; the trailing user message becomes the prompt).
- Tools — each `AIToolProtocol` is bridged to a `FoundationModels.Tool`; calls surface through the same loop as every other provider.
- `generateObject` — a `.json` response format maps your JSON Schema onto the framework's constrained/guided decoding (`GenerationSchema`); JSON streams back as `.textDelta`.
- Chat: `ChatSession(model: FoundationModelsModel())` gives a fully offline chat UI.

## Capability limits

- No reasoning and no vision (see the compatibility matrix — Foundation Models is Tools + Structured output only).
- `streamText` emits `.textDelta` and a final `.finish`; it does not emit `.reasoningDelta`.
- Guided generation supports `object` / `array` / `string` / `number` / `integer` / `boolean` and string `enum`s. Any other JSON Schema shape throws `AIError.invalidRequest("Unsupported JSON Schema for guided generation: …")`.
- Only `temperature` and `maxOutputTokens` from the request map onto `GenerationOptions`; other sampling knobs (`topP`, `topK`, penalties, `seed`, `stopSequences`) are ignored.

## Error taxonomy

Framework errors are mapped to `AIError` (see errors.md):

- Guardrail violations / refusals → a clean `.finish(reason: .contentFilter, …)`, not a throw.
- Context overflow → `AIError.invalidRequest`.
- Rate limiting → `AIError.http(status: 429, …)`.
- Unavailable model assets (Apple Intelligence still downloading) → `AIError.transport` with a message telling the user to check System Settings › Apple Intelligence and retry.
- Generic `FoundationModels` `NSError`s (including `ModelManagerError`) → `AIError.transport` with a human-readable message instead of a cryptic code.

## Gotchas

- Referencing the type outside `#if canImport(FoundationModels)` / below the iOS 26 SDK will not compile — keep call sites guarded or fully targeted at the 26 SDK.
- `isAvailable` can be `false` at runtime even on a supported OS (device unsupported, or Apple Intelligence off / still downloading). Always branch; never assume.
- Unentitled processes on some OS builds cannot run on-device inference at all; the mapped error message says exactly that.
- On this repo's dev Mac, on-device inference is currently broken (sanitizer asset failure) and PCC traps without the entitlement — test the cloud fallback branch, not the on-device branch, locally.
