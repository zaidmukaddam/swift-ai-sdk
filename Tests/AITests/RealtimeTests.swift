import XCTest
@testable import AI

final class RealtimeTests: XCTestCase {

    func testGetRealtimeToolDefinitions() {
        let tool = Tool(
            name: "getWeather", description: "Get the weather.",
            parameters: .object(["type": .string("object")])
        ) { _ in .null }
        let definitions = getRealtimeToolDefinitions(tools: [tool])
        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions[0].name, "getWeather")
        XCTAssertEqual(definitions[0].description, "Get the weather.")
        XCTAssertEqual(definitions[0].parameters["type"]?.stringValue, "object")
    }

    func testOpenAIParsesServerEvents() {
        let model = OpenAIRealtimeModel("gpt-realtime", apiKey: "k")

        let created = model.parseServerEvent(.object([
            "type": "session.created", "session": .object(["id": .string("sess_1")])
        ]))
        guard case .sessionCreated(let sessionID, _) = created[0] else {
            return XCTFail("expected sessionCreated")
        }
        XCTAssertEqual(sessionID, "sess_1")

        let text = model.parseServerEvent(.object([
            "type": "response.output_text.delta",
            "response_id": .string("r1"), "item_id": .string("i1"),
            "delta": .string("Hel")
        ]))
        guard case .textDelta(let responseID, let itemID, let delta, _) = text[0] else {
            return XCTFail("expected textDelta")
        }
        XCTAssertEqual([responseID, itemID, delta], ["r1", "i1", "Hel"])

        let call = model.parseServerEvent(.object([
            "type": "response.function_call_arguments.done",
            "response_id": .string("r1"), "item_id": .string("i2"),
            "call_id": .string("c1"), "name": .string("getWeather"),
            "arguments": .string("{\"city\":\"Mumbai\"}")
        ]))
        guard case .functionCallArgumentsDone(_, _, let callID, let name, let args, _) = call[0]
        else { return XCTFail("expected functionCallArgumentsDone") }
        XCTAssertEqual(callID, "c1")
        XCTAssertEqual(name, "getWeather")
        XCTAssertEqual(args, "{\"city\":\"Mumbai\"}")

        let error = model.parseServerEvent(.object([
            "type": "error", "error": .object(["message": .string("boom")])
        ]))
        guard case .error(let message, _, _) = error[0] else {
            return XCTFail("expected error")
        }
        XCTAssertEqual(message, "boom")

        let unknown = model.parseServerEvent(.object([
            "type": "rate_limits.updated"
        ]))
        guard case .custom(let rawType, _) = unknown[0] else {
            return XCTFail("expected custom")
        }
        XCTAssertEqual(rawType, "rate_limits.updated")
    }

    func testOpenAISessionConfigShape() {
        let model = OpenAIRealtimeModel("gpt-realtime", apiKey: "k")
        let config = RealtimeSessionConfig(
            instructions: "Be concise.",
            voice: "alloy",
            inputAudioTranscription: .init(),
            turnDetection: .init(type: .serverVAD, silenceDurationMs: 500),
            tools: [RealtimeToolDefinition(
                name: "getWeather", description: "d",
                parameters: .object(["type": .string("object")])
            )]
        )
        let session = model.buildSessionConfig(config)
        XCTAssertEqual(session["type"]?.stringValue, "realtime")
        XCTAssertEqual(session["model"]?.stringValue, "gpt-realtime")
        XCTAssertEqual(session["instructions"]?.stringValue, "Be concise.")
        XCTAssertEqual(session["audio"]?["output"]?["voice"]?.stringValue, "alloy")
        let input = session["audio"]?["input"]
        XCTAssertEqual(input?["turn_detection"]?["type"]?.stringValue, "server_vad")
        XCTAssertEqual(input?["turn_detection"]?["silence_duration_ms"]?.intValue, 500)
        XCTAssertEqual(
            input?["transcription"]?["model"]?.stringValue, "gpt-realtime-whisper"
        )
        XCTAssertEqual(session["tools"]?.arrayValue?.count, 1)
        XCTAssertEqual(session["tool_choice"]?.stringValue, "auto")
    }

    func testOpenAIDisabledVADAndClientEvents() {
        let model = OpenAIRealtimeModel("gpt-realtime", apiKey: "k")
        let session = model.buildSessionConfig(RealtimeSessionConfig(
            turnDetection: .init(type: .disabled)
        ))
        guard case .null? = session["audio"]?["input"]?["turn_detection"] else {
            return XCTFail("disabled VAD must serialize as null")
        }

        let text = model.serializeClientEvent(
            .conversationItemCreate(.textMessage("Hi"))
        )
        XCTAssertEqual(text?["type"]?.stringValue, "conversation.item.create")
        XCTAssertEqual(text?["item"]?["type"]?.stringValue, "message")
        XCTAssertEqual(
            text?["item"]?["content"]?.arrayValue?.first?["type"]?.stringValue, "input_text"
        )

        let output = model.serializeClientEvent(.conversationItemCreate(
            .functionCallOutput(callID: "c1", name: "getWeather", output: "{\"ok\":true}")
        ))
        XCTAssertEqual(output?["item"]?["type"]?.stringValue, "function_call_output")
        XCTAssertEqual(output?["item"]?["call_id"]?.stringValue, "c1")

        let truncate = model.serializeClientEvent(
            .conversationItemTruncate(itemID: "i1", contentIndex: 0, audioEndMs: 1200)
        )
        XCTAssertEqual(truncate?["type"]?.stringValue, "conversation.item.truncate")
        XCTAssertEqual(truncate?["audio_end_ms"]?.intValue, 1200)
    }

    func testOpenAIWebSocketConfigAndURL() {
        let model = OpenAIRealtimeModel("gpt-realtime", apiKey: "k")
        XCTAssertEqual(
            OpenAIRealtimeModel.webSocketURL(
                baseURL: URL(string: "https://api.openai.com/v1")!, modelID: "gpt-realtime"
            ),
            "wss://api.openai.com/v1/realtime?model=gpt-realtime"
        )
        let config = model.webSocketConfig(
            token: "tok", url: "wss://api.openai.com/v1/realtime?model=gpt-realtime"
        )
        XCTAssertEqual(config.protocols, ["realtime", "openai-insecure-api-key.tok"])
    }

    func testXaiTextEventSpellingAndAuth() {
        let model = XaiRealtimeModel("grok-voice-latest", apiKey: "k")
        let text = model.parseServerEvent(.object([
            "type": "response.text.delta",
            "response_id": .string("r1"), "item_id": .string("i1"),
            "delta": .string("Hi")
        ]))
        guard case .textDelta = text[0] else {
            return XCTFail("xAI spells text deltas response.text.delta")
        }

        XCTAssertNil(model.serializeClientEvent(
            .conversationItemTruncate(itemID: "i", contentIndex: 0, audioEndMs: 1)
        ))

        XCTAssertEqual(
            model.webSocketConfig(token: "tok", url: "wss://api.x.ai/v1/realtime").protocols,
            ["xai-client-secret.tok"]
        )
    }

    func testXaiSessionConfigIsFlat() {
        let model = XaiRealtimeModel("grok-voice-latest", apiKey: "k")
        let session = model.buildSessionConfig(RealtimeSessionConfig(
            instructions: "Hi.",
            voice: "ember",
            turnDetection: .init(type: .semanticVAD),
            providerOptions: .object(["tools": .array([.object(["type": .string("web_search")])])])
        ))
        XCTAssertEqual(session["voice"]?.stringValue, "ember")
        XCTAssertEqual(session["turn_detection"]?["type"]?.stringValue, "server_vad")
        XCTAssertEqual(session["tools"]?.arrayValue?.count, 1)
        XCTAssertNil(session["type"])
    }

    func testGoogleRealtimeURLs() {
        let base = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        XCTAssertEqual(
            GoogleRealtimeModel.authTokensURL(base),
            "https://generativelanguage.googleapis.com/v1alpha/auth_tokens"
        )
        XCTAssertEqual(
            GoogleRealtimeModel.webSocketURL(base),
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
        )
        let config = GoogleRealtimeModel("gemini-live", apiKey: "k")
            .webSocketConfig(token: "tok/en", url: "wss://example.com/ws")
        XCTAssertTrue(config.url.absoluteString.contains("access_token=tok"))
        XCTAssertTrue(config.protocols.isEmpty)
    }

    func testGoogleSessionConfigShape() {
        let model = GoogleRealtimeModel("gemini-3.1-flash-live-preview", apiKey: "k")
        let session = model.buildSessionConfig(RealtimeSessionConfig(
            instructions: "Be brief.",
            voice: "Puck",
            inputAudioTranscription: .init(),
            tools: [RealtimeToolDefinition(
                name: "getWeather",
                parameters: .object(["type": .string("object")])
            )],
            providerOptions: .object([
                "google": .object([
                    "translationConfig": .object(["targetLanguageCode": .string("hi")])
                ])
            ])
        ))
        XCTAssertEqual(
            session["model"]?.stringValue, "models/gemini-3.1-flash-live-preview"
        )
        XCTAssertEqual(
            session["generationConfig"]?["responseModalities"]?.arrayValue?.first?.stringValue, "AUDIO"
        )
        XCTAssertEqual(
            session["generationConfig"]?["speechConfig"]?["voiceConfig"]?["prebuiltVoiceConfig"]?["voiceName"]?.stringValue,
            "Puck"
        )
        XCTAssertEqual(
            session["systemInstruction"]?["parts"]?.arrayValue?.first?["text"]?.stringValue, "Be brief."
        )
        XCTAssertEqual(
            session["tools"]?.arrayValue?.first?["functionDeclarations"]?.arrayValue?.first?["name"]?.stringValue,
            "getWeather"
        )
        XCTAssertNotNil(session["inputAudioTranscription"])
        XCTAssertEqual(
            session["generationConfig"]?["translationConfig"]?["targetLanguageCode"]?.stringValue,
            "hi"
        )
    }

    func testGoogleServerContentFansOut() {
        let model = GoogleRealtimeModel("gemini-live", apiKey: "k")

        let setup = model.parseServerEvent(.object(["setupComplete": .object([:])]))
        guard case .sessionCreated = setup[0] else { return XCTFail("expected sessionCreated") }

        let events = model.parseServerEvent(.object([
            "serverContent": .object([
                "modelTurn": .object(["parts": .array([
                    .object(["inlineData": .object(["data": .string("QUJD")])]),
                    .object(["text": .string("Hello")])
                ])]),
                "outputTranscription": .object(["text": .string("Hel")]),
                "turnComplete": .bool(true)
            ])
        ]))
        let kinds = events.map { event -> String in
            switch event {
            case .audioDelta: return "audioDelta"
            case .textDelta: return "textDelta"
            case .audioTranscriptDelta: return "transcriptDelta"
            case .audioDone: return "audioDone"
            case .textDone: return "textDone"
            case .audioTranscriptDone: return "transcriptDone"
            case .responseDone: return "responseDone"
            default: return "other"
            }
        }
        XCTAssertEqual(kinds, [
            "audioDelta", "textDelta", "transcriptDelta",
            "audioDone", "textDone", "transcriptDone", "responseDone"
        ])

        let trailing = model.parseServerEvent(.object([
            "serverContent": .object([
                "outputTranscription": .object(["text": .string("lo")])
            ])
        ]))
        guard case .audioTranscriptDelta(let sameResponse, _, _, _) = trailing[0] else {
            return XCTFail("expected transcript delta")
        }
        XCTAssertEqual(sameResponse, "google-resp-0")

        let nextTurn = model.parseServerEvent(.object([
            "serverContent": .object([
                "modelTurn": .object(["parts": .array([
                    .object(["text": .string("Next")])
                ])])
            ])
        ]))
        guard case .textDelta(let nextResponse, _, _, _) = nextTurn[0] else {
            return XCTFail("expected text delta")
        }
        XCTAssertEqual(nextResponse, "google-resp-1")
    }

    func testGoogleToolCallsAndClientEvents() {
        let model = GoogleRealtimeModel("gemini-live", apiKey: "k")

        let events = model.parseServerEvent(.object([
            "toolCall": .object(["functionCalls": .array([
                .object([
                    "id": .string("c1"), "name": .string("getWeather"),
                    "args": .object(["city": .string("Mumbai")])
                ])
            ])])
        ]))
        XCTAssertEqual(events.count, 2)
        guard case .functionCallArgumentsDone(_, _, let callID, let name, let args, _) = events[1]
        else { return XCTFail("expected done event") }
        XCTAssertEqual(callID, "c1")
        XCTAssertEqual(name, "getWeather")
        XCTAssertTrue(args.contains("Mumbai"))

        let before = model.serializeClientEvent(.inputAudioAppend(base64Audio: "QUJD"))
        XCTAssertEqual(
            before?["realtimeInput"]?["audio"]?["mimeType"]?.stringValue,
            "audio/pcm;rate=16000"
        )
        _ = model.serializeClientEvent(.sessionUpdate(RealtimeSessionConfig(
            inputAudioFormat: .init(rate: 24000)
        )))
        let after = model.serializeClientEvent(.inputAudioAppend(base64Audio: "QUJD"))
        XCTAssertEqual(
            after?["realtimeInput"]?["audio"]?["mimeType"]?.stringValue,
            "audio/pcm;rate=24000"
        )

        let commit = model.serializeClientEvent(.inputAudioCommit)
        XCTAssertEqual(commit?["realtimeInput"]?["audioStreamEnd"]?.boolValue, true)

        let text = model.serializeClientEvent(.conversationItemCreate(.textMessage("Hi")))
        XCTAssertEqual(text?["realtimeInput"]?["text"]?.stringValue, "Hi")

        let output = model.serializeClientEvent(.conversationItemCreate(
            .functionCallOutput(callID: "c1", name: "getWeather", output: "{\"t\":72}")
        ))
        let functionResponse = output?["toolResponse"]?["functionResponses"]?.arrayValue?.first
        XCTAssertEqual(functionResponse?["id"]?.stringValue, "c1")
        XCTAssertEqual(functionResponse?["name"]?.stringValue, "getWeather")
        XCTAssertEqual(functionResponse?["response"]?["t"]?.intValue, 72)

        XCTAssertNil(model.serializeClientEvent(.responseCreate()))
    }

    private func raw(_ type: String) -> JSONValue { .object(["type": .string(type)]) }

    func testReducerStreamsTextIntoMessages() {
        let reducer = RealtimeConversationReducer()
        _ = reducer.reduce(.textDelta(responseID: "r1", itemID: "i1", delta: "Hel", raw: raw("t")))
        _ = reducer.reduce(.textDelta(responseID: "r1", itemID: "i1", delta: "lo", raw: raw("t")))
        XCTAssertEqual(reducer.messages.count, 1)
        XCTAssertEqual(reducer.messages[0].role, .assistant)
        XCTAssertEqual(reducer.messages[0].text, "Hello")

        _ = reducer.reduce(.textDone(responseID: "r1", itemID: "i1", text: nil, raw: raw("t")))
        guard case .text(let part) = reducer.messages[0].parts[0] else {
            return XCTFail("expected text part")
        }
        XCTAssertEqual(part.state, .done)
    }

    func testReducerInsertsInputTranscriptionWhereAudioCommitted() {
        let reducer = RealtimeConversationReducer()
        _ = reducer.reduce(.audioCommitted(itemID: "in1", previousItemID: nil, raw: raw("c")))
        _ = reducer.reduce(.textDelta(responseID: "r1", itemID: "i1", delta: "Answer", raw: raw("t")))
        _ = reducer.reduce(.inputTranscriptionCompleted(
            itemID: "in1", transcript: "Question", raw: raw("q")
        ))
        XCTAssertEqual(reducer.messages.count, 2)
        XCTAssertEqual(reducer.messages[0].role, .user)
        XCTAssertEqual(reducer.messages[0].text, "Question")
        XCTAssertEqual(reducer.messages[1].role, .assistant)
    }

    func testReducerToolCallFlow() throws {
        let reducer = RealtimeConversationReducer()
        _ = reducer.reduce(.functionCallArgumentsDelta(
            responseID: "r1", itemID: "i1", callID: "c1", delta: "{\"city\":", raw: raw("d")
        ))
        guard case .tool(let streaming) = reducer.messages[0].parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(streaming.state, .inputStreaming)

        let effects = reducer.reduce(.functionCallArgumentsDone(
            responseID: "r1", itemID: "i1", callID: "c1",
            name: "getWeather", arguments: "{\"city\":\"Mumbai\"}", raw: raw("d")
        ))
        guard case .toolCall(let call)? = effects.first else {
            return XCTFail("expected toolCall effect")
        }
        XCTAssertEqual(call.name, "getWeather")
        XCTAssertEqual(call.arguments["city"]?.stringValue, "Mumbai")

        let (name, outputJSON) = reducer.addToolOutput(
            callID: "c1", output: .object(["temperature": .number(72)])
        )
        XCTAssertEqual(name, "getWeather")
        XCTAssertTrue(outputJSON.contains("72"))
        guard case .tool(let finished) = reducer.messages[0].parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(finished.state, .outputAvailable)
        XCTAssertEqual(finished.toolName, "getWeather")
    }

    func testReducerAudioDeltaBecomesPlaybackEffect() {
        let reducer = RealtimeConversationReducer()
        let effects = reducer.reduce(.audioDelta(
            responseID: "r1", itemID: "i1", delta: "QUJD", raw: raw("a")
        ))
        guard case .playAudio(let itemID, let base64)? = effects.first else {
            return XCTFail("expected playAudio effect")
        }
        XCTAssertEqual(itemID, "i1")
        XCTAssertEqual(base64, "QUJD")
        XCTAssertTrue(reducer.messages.isEmpty)
    }

    func testReducerCapsEventLog() {
        let reducer = RealtimeConversationReducer(maxEvents: 3)
        for index in 0..<5 {
            _ = reducer.reduce(.custom(rawType: "event-\(index)", raw: raw("x")))
        }
        XCTAssertEqual(reducer.events.count, 3)
        guard case .custom(let rawType, _) = reducer.events[0] else {
            return XCTFail("expected custom")
        }
        XCTAssertEqual(rawType, "event-2")
    }
}
