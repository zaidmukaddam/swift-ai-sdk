import XCTest
@testable import AI

final class NewProviderPacksTests: XCTestCase {

    private func body(_ request: URLRequest) -> JSONValue {
        guard let data = request.httpBody,
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return value
    }

    func testGroqBrowserSearchToolSentAsRawEntry() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [GroqModel.Tools.browserSearch(), GroqModel.Tools.codeExecution()],
            maxOutputTokens: 100
        )
        let value = OpenAIChatModel.requestBody(
            for: request, modelID: "groq/compound", reasoningStyle: .groq, providerName: "groq"
        ).objectValue ?? [:]
        let tools = value["tools"]?.arrayValue ?? []
        XCTAssertTrue(tools.contains { $0["type"] == "browser_search" })
        XCTAssertTrue(tools.contains { $0["type"] == "code_execution" })
    }

    func testPerplexityChunkDecodesSearchResults() throws {
        let json = #"{"search_results":[{"title":"Weather","url":"https://ex.com/w","date":"2026-07-01"}],"choices":[{"delta":{"content":"hi"}}]}"#
            .data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: json)
        XCTAssertEqual(chunk.search_results?.first?.title, "Weather")
        XCTAssertEqual(chunk.search_results?.first?.url, "https://ex.com/w")
    }

    func testPerplexityChunkDecodesImagesAndRelatedQuestions() throws {
        let json = #"{"images":[{"image_url":"https://ex.com/a.jpg"}],"related_questions":["What next?"],"choices":[{"delta":{"content":"hi"}}]}"#
            .data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: json)
        XCTAssertEqual(chunk.images?.arrayValue?.first?["image_url"]?.stringValue, "https://ex.com/a.jpg")
        XCTAssertEqual(chunk.related_questions?.arrayValue?.first?.stringValue, "What next?")
    }

    func testOpenAIChunkDecodesLogprobs() throws {
        let json = #"{"choices":[{"delta":{"content":"hi"},"logprobs":{"content":[{"token":"hi","logprob":-0.1}]}}]}"#
            .data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: json)
        let entry = chunk.choices?.first?.logprobs?.content?.first
        XCTAssertEqual(entry?["token"]?.stringValue, "hi")
        XCTAssertEqual(entry?["logprob"]?.doubleValue, -0.1)
    }

    func testMergingMetadataCombinesProviderBlocks() {
        let a: JSONValue = .object(["perplexity": .object(["images": .array([])])])
        let merged = JSONValue.mergingMetadata(a, .object(["openai": .object(["logprobs": .bool(true)])]))
        XCTAssertNotNil(merged["perplexity"])
        XCTAssertEqual(merged["openai"]?["logprobs"]?.boolValue, true)
    }

    func testBedrockSigV4SignsRequest() throws {
        let model = BedrockModel(
            "anthropic.claude-sonnet-5-v1:0",
            region: "us-east-1",
            accessKeyID: "AKIDEXAMPLE",
            secretAccessKey: "wSecretExampleKey"
        )
        let request = try model.buildURLRequest(
            LanguageModelRequest(messages: [.user("hi")], maxOutputTokens: 100)
        )
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/"))
        XCTAssertTrue(auth.contains("/us-east-1/bedrock/aws4_request"))
        XCTAssertTrue(auth.contains("SignedHeaders=content-type;host;x-amz-date"))
        XCTAssertTrue(auth.contains("Signature="))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Amz-Date"))
    }

    func testBedrockFallsBackToBearerWithoutSigV4Creds() throws {
        let model = BedrockModel(
            "anthropic.claude-sonnet-5-v1:0",
            apiKey: "bearer-token",
            accessKeyID: "",
            secretAccessKey: ""
        )
        let request = try model.buildURLRequest(
            LanguageModelRequest(messages: [.user("hi")], maxOutputTokens: 100)
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bearer-token")
    }

    func testMoonshotAlibabaHuggingFaceConfig() {
        XCTAssertEqual(MoonshotModel("kimi-k2").engine.provider, "moonshot")
        XCTAssertEqual(AlibabaModel("qwen-max").engine.provider, "alibaba")
        XCTAssertEqual(HuggingFaceModel("meta-llama/Llama-3.3-70B-Instruct").provider, "huggingface")
    }

    func testAlibabaEmbeddingUsesNativeDashScopeEndpoint() throws {
        let model = AlibabaEmbeddingModel("text-embedding-v4", apiKey: "k", dimension: 1024)
        let request = try model.buildURLRequest(["hello", "world"])
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://dashscope-intl.aliyuncs.com/api/v1/services/embeddings/text-embedding/text-embedding"
        )
        let value = body(request)
        XCTAssertEqual(value["model"], "text-embedding-v4")
        XCTAssertEqual(value["input"]?["texts"]?.arrayValue?.count, 2)
        XCTAssertEqual(value["parameters"]?["dimension"]?.intValue, 1024)
    }

    func testVoyageEmbeddingBody() throws {
        let model = VoyageEmbeddingModel("voyage-3.5", apiKey: "k", inputType: .document)
        let value = body(try model.buildURLRequest(["hello", "world"]))
        XCTAssertEqual(value["model"], "voyage-3.5")
        XCTAssertEqual(value["input"]?.arrayValue?.count, 2)
        XCTAssertEqual(value["input_type"], "document")
    }

    func testVoyageRerankBody() throws {
        let model = VoyageRerankingModel("rerank-2.5", apiKey: "k")
        let request = try model.buildURLRequest(query: "q", documents: ["a", "b", "c"], topN: 2)
        XCTAssertEqual(request.url?.absoluteString, "https://api.voyageai.com/v1/rerank")
        let value = body(request)
        XCTAssertEqual(value["query"], "q")
        XCTAssertEqual(value["documents"]?.arrayValue?.count, 3)
        XCTAssertEqual(value["top_k"]?.intValue, 2)
    }

    func testCartesiaSpeechBodyAndVersionHeader() throws {
        let model = CartesiaSpeechModel("sonic-2", apiKey: "k")
        let request = try model.buildURLRequest(
            SpeechModelRequest(text: "hi there", voice: "voice-123", outputFormat: "wav")
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cartesia-Version"), "2026-03-01")
        let value = body(request)
        XCTAssertEqual(value["model_id"], "sonic-2")
        XCTAssertEqual(value["transcript"], "hi there")
        XCTAssertEqual(value["voice"]?["id"], "voice-123")
        XCTAssertEqual(value["output_format"]?["container"], "wav")
    }

    func testBlackForestLabsCreateBody() throws {
        let model = BlackForestLabsImageModel("flux-pro-1.1", apiKey: "k")
        let request = try model.buildCreateRequest(
            ImageModelRequest(prompt: "a cat", size: "1024x768", seed: 7)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.bfl.ai/v1/flux-pro-1.1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-key"), "k")
        let value = body(request)
        XCTAssertEqual(value["prompt"], "a cat")
        XCTAssertEqual(value["width"]?.intValue, 1024)
        XCTAssertEqual(value["height"]?.intValue, 768)
        XCTAssertEqual(value["seed"]?.intValue, 7)
    }

    func testByteDanceVideoContentArray() throws {
        let model = ByteDanceVideoModel("seedance-1-0-pro", apiKey: "k")
        let request = try model.buildCreateRequest(VideoModelRequest(prompt: "a dog running"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks"
        )
        let value = body(request)
        XCTAssertEqual(value["content"]?.arrayValue?.first?["text"], "a dog running")
        XCTAssertEqual(value["content"]?.arrayValue?.first?["type"], "text")
    }

    func testKlingJWTHasThreeSegmentsAndHS256Header() throws {
        let model = KlingVideoModel("kling-v2-master", accessKey: "ak", secretKey: "sk")
        let token = try model.authToken()
        let segments = token.split(separator: ".")
        XCTAssertEqual(segments.count, 3)

        func decode(_ segment: Substring) -> JSONValue {
            var s = String(segment).replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while s.count % 4 != 0 { s += "=" }
            guard let data = Data(base64Encoded: s),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return .null }
            return value
        }
        XCTAssertEqual(decode(segments[0])["alg"], "HS256")
        XCTAssertEqual(decode(segments[1])["iss"], "ak")
    }

    func testAlibabaVideoAsyncSubmit() throws {
        let model = AlibabaVideoModel("wan2.6-t2v", apiKey: "k")
        let request = try model.buildCreateRequest(VideoModelRequest(prompt: "a river at dawn"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-DashScope-Async"), "enable")
        let value = body(request)
        XCTAssertEqual(value["model"], "wan2.6-t2v")
        XCTAssertEqual(value["input"]?["prompt"], "a river at dawn")
    }

    func testKlingRouteStripsSuffixAndNormalizes() {
        let t2v = KlingVideoModel.route("kling-v2-master-t2v", hasImage: false)
        XCTAssertEqual(t2v.endpoint, "text2video")
        XCTAssertEqual(t2v.apiModelName, "kling-v2-master")

        let i2v = KlingVideoModel.route("kling-v2.1-master-i2v", hasImage: true)
        XCTAssertEqual(i2v.endpoint, "image2video")
        XCTAssertEqual(i2v.apiModelName, "kling-v2-1-master")

        let mc = KlingVideoModel.route("kling-v2.6-motion-control", hasImage: false)
        XCTAssertEqual(mc.endpoint, "motion-control")
        XCTAssertEqual(mc.apiModelName, "kling-v2-6")

        let bare = KlingVideoModel.route("kling-v2-master", hasImage: true)
        XCTAssertEqual(bare.endpoint, "image2video")
        XCTAssertEqual(bare.apiModelName, "kling-v2-master")
    }

    func testProdiaJobBody() throws {
        let model = ProdiaImageModel("inference.flux.dev.txt2img.v1", apiKey: "k")
        let request = try model.buildURLRequest(ImageModelRequest(prompt: "sunset"))
        XCTAssertEqual(request.url?.absoluteString, "https://inference.prodia.com/v2/job")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        let value = body(request)
        XCTAssertEqual(value["type"], "inference.flux.dev.txt2img.v1")
        XCTAssertEqual(value["config"]?["prompt"], "sunset")
    }

    func testQuiverAISvgEndpoint() throws {
        let model = QuiverAIImageModel(apiKey: "k")
        let request = try model.buildURLRequest(ImageModelRequest(prompt: "a logo"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.quiver.ai/v1/svgs/generations")
        XCTAssertEqual(body(request)["prompt"], "a logo")
    }
}
