# Images, speech, transcription, video

Four top-level `async throws` functions — `generateImage`, `generateSpeech`, `transcribe`, `generateVideo` — each take a model conforming to a small protocol (`ImageModel`/`SpeechModel`/`TranscriptionModel`/`VideoModel`), so every provider pack plugs into the same call. `import AI`. Every function retries (`maxRetries: Int = 2`). Model ids are positional (unlabeled first arg); `apiKey` defaults to the provider's env var.

## generateImage

```swift
public func generateImage(
    model: any ImageModel,
    prompt: String,
    images: [ImageContent] = [],          // source images → switches OpenAI to the edits endpoint
    n: Int = 1,
    size: String? = nil,                  // e.g. "1024x1024"
    aspectRatio: String? = nil,           // e.g. "16:9" (whichever the provider takes)
    seed: Int? = nil,
    providerOptions: JSONValue? = nil,    // e.g. ["openai": ["quality": "hd", "style": "vivid"]]
    maxRetries: Int = 2
) async throws -> GenerateImageResult

public struct GenerateImageResult {
    public var image: Data                // first image
    public var images: [Data]
    public var revisedPrompts: [String?]  // providers that rewrite the prompt report it
}
```

Models (`ImageModel`):

```swift
OpenAIImageModel(_ modelID: String, apiKey: String? = nil, ...)          // OPENAI_API_KEY
FalImageModel(_ modelID: String, apiKey: String? = nil, ...)             // FAL_API_KEY / FAL_KEY
LumaImageModel(_ modelID: String = "photon-1", apiKey: String? = nil, ...) // LUMA_API_KEY, polls
ReplicateImageModel(_ modelID: String, apiKey: String? = nil, ...)       // REPLICATE_API_TOKEN
```

```swift
let result = try await generateImage(
    model: OpenAIImageModel("gpt-image-2"),
    prompt: "A watercolor fox in a snowy forest",
    size: "1024x1024"
)
try result.image.write(to: outputURL)          // image is Data

let edited = try await generateImage(
    model: OpenAIImageModel("gpt-image-2"),
    prompt: "Make the sky stormy",
    images: [sourceImage]                        // ImageContent, uses edits endpoint
)
```

## generateSpeech

```swift
public func generateSpeech(
    model: any SpeechModel,
    text: String,
    voice: String? = nil,
    instructions: String? = nil,          // e.g. "speak in a slow, steady tone"
    speed: Double? = nil,                 // multiplier; OpenAI 0.25–4
    outputFormat: String? = nil,          // "mp3", "wav"
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateSpeechResult

public struct GenerateSpeechResult { public var audio: Data; public var mediaType: String }
```

Models (`SpeechModel`):

```swift
OpenAISpeechModel(_ modelID: String, ...)                                    // OPENAI_API_KEY
ElevenLabsSpeechModel(_ modelID: String, ...)                                // ELEVENLABS_API_KEY
LMNTSpeechModel(_ modelID: String = "aurora", ...)                           // LMNT_API_KEY
HumeSpeechModel(_ modelID: String = "default", ...)                          // HUME_API_KEY, voice-only
DeepgramSpeechModel(_ modelID: String = "aura-2-thalia-en", ...)             // DEEPGRAM_API_KEY
SarvamSpeechModel(_ modelID: String = "bulbul:v3", apiKey: String? = nil,
                  targetLanguage: String = "en-IN", ...)                     // SARVAM_API_KEY
```

```swift
let speech = try await generateSpeech(
    model: OpenAISpeechModel("gpt-4o-mini-tts"),
    text: "The quick brown fox jumped over the lazy dog.",
    voice: "alloy"
)
try speech.audio.write(to: URL(fileURLWithPath: "/tmp/hello.mp3"))
```

Sarvam requires a `targetLanguage` (its own init parameter, e.g. `"hi-IN"`), not passed through `generateSpeech`. Each provider has its own voice catalog; pass the provider's voice id to `voice:`.

## transcribe

```swift
public func transcribe(
    model: any TranscriptionModel,
    audio: Data,
    mediaType: String,                    // e.g. "audio/mpeg"
    providerOptions: JSONValue? = nil,    // e.g. ["openai": ["language": "en", "temperature": 0]]
    maxRetries: Int = 2
) async throws -> TranscriptionResult

public struct TranscriptionResult {
    public var text: String
    public var segments: [TranscriptionSegment]   // .text, .startSecond, .endSecond
    public var language: String?
    public var durationInSeconds: Double?
}
```

Models (`TranscriptionModel`):

```swift
OpenAITranscriptionModel(_ modelID: String, ...)                     // OPENAI_API_KEY, sync multipart
ElevenLabsTranscriptionModel(_ modelID: String = "scribe_v1", ...)   // ELEVENLABS_API_KEY, sync
DeepgramTranscriptionModel(_ modelID: String = "nova-3", ...)        // DEEPGRAM_API_KEY, sync
AssemblyAITranscriptionModel(_ modelID: String = "universal", ...)   // ASSEMBLYAI_API_KEY, async
RevAITranscriptionModel(_ modelID: String = "machine", ...)          // REVAI_API_KEY, async
GladiaTranscriptionModel(_ modelID: String = "default", ...)         // GLADIA_API_KEY, async
SarvamTranscriptionModel(_ modelID: String = "saaras:v3", ...)       // SARVAM_API_KEY, sync multipart
```

```swift
let transcript = try await transcribe(
    model: OpenAITranscriptionModel("whisper-1"),
    audio: audioData,
    mediaType: "audio/mpeg"
)
print(transcript.text)
for segment in transcript.segments {
    print("\(segment.startSecond)s to \(segment.endSecond)s:", segment.text)
}
```

Async providers (AssemblyAI, Rev.ai, Gladia) hide submit/poll/fetch behind the single `transcribe` call (they take `pollInterval`/`pollTimeout` init args). Groq-hosted Whisper works via `OpenAITranscriptionModel` with Groq's `baseURL`.

## generateVideo

```swift
public func generateVideo(
    model: any VideoModel,
    prompt: String,
    image: ImageContent? = nil,           // start frame → animate a still
    aspectRatio: String? = nil,           // e.g. "16:9"
    duration: Int? = nil,                 // seconds
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateVideoResult

public struct GenerateVideoResult {
    public var video: Data?               // first inline video, if delivered as bytes
    public var videos: [Data]
    public var urls: [URL]                // if delivered as links
    public var mediaType: String          // default "video/mp4"
}
```

Models (`VideoModel`):

```swift
XaiVideoModel(_ modelID: String, ...)                    // XAI_API_KEY, polls until rendered
LumaVideoModel(_ modelID: String = "ray-2", ...)         // LUMA_API_KEY, Dream Machine, polls
```

```swift
let result = try await generateVideo(
    model: XaiVideoModel("grok-imagine-video-1.5"),
    prompt: "A paper boat drifting down a rainy street, cinematic",
    duration: 6
)
print(result.urls.first?.absoluteString ?? "no url")

let animated = try await generateVideo(
    model: XaiVideoModel("grok-imagine-video-1.5"),
    prompt: "The fox blinks and snow falls gently",
    image: ImageContent(data: still)             // first frame
)
```

## ImageContent

Used for image edits (`images:`) and video start frames (`image:`):

```swift
public struct ImageContent {
    public init(data: Data, mediaType: String? = nil)
    public init(url: URL, mediaType: String? = nil)
}
```

## Gotchas

- **Model id is positional** — `OpenAIImageModel("gpt-image-2")`, not `model:`. `apiKey` and the rest are labeled.
- **`result.image` / `result.video` are convenience firsts** — `image` is `Data` (non-optional, throws if the response had none); `video` is `Data?`. Full sets live in `images`/`videos`; links in `urls`.
- **Video delivery varies** — some providers return `urls`, others inline `videos` bytes. Check both; `generateVideo` throws only if both are empty.
- **Sarvam needs `targetLanguage`** at construction (default `"en-IN"` for speech), separate from the transcription/speech call args.
- **Retries are automatic** (`maxRetries` default 2) and each function throws `AIError.decoding` on an empty result; async transcription/video providers additionally have `pollInterval`/`pollTimeout` init knobs.
- **`providerOptions` is keyed by provider** (`["openai": [...]]`, `["luma": [...]]`) and merged into that provider's native create call; keys under the wrong provider are ignored.
- **OpenAI image edits vs. generation** is switched automatically by passing `images:` — no separate function.
