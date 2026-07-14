# Swift AI example apps

Two real SwiftUI example apps, verified on the iOS simulator:

- `StreamTextDemo` — a chat UI over `streamText` with the tool loop, talking to a
  local Ollama server (the simulator shares the Mac's loopback, so no setup).
- `RealtimeDemo` — a voice UI over `RealtimeSession`: pick xAI, OpenAI, or Google,
  paste an API key (or export it), and it speaks through your speakers, streams
  your microphone, transcribes both sides, and runs a client-side tool.

## Run on iOS

```bash
brew install xcodegen       # once
cd Apps
xcodegen generate
open SwiftAIApps.xcodeproj
```

Choose the `StreamTextDemo` or `RealtimeDemo` scheme and run it on an iPhone
simulator.

For macOS, the same sources can be launched with:

```bash
cd Apps
swift run StreamTextDemo
# or
swift run RealtimeDemo
```

Both apps also take a `--smoke` launch argument for scripted, self-verifying
runs. Keys entered in the example UI live only for the current process. A
production app should mint short-lived realtime credentials on a server
instead of shipping long-lived provider keys in the client.
