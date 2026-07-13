import XCTest
@testable import AI

final class UpstreamDriftTests: XCTestCase {

    func testGroqCachedTokensDecodeFromXGroqEnvelope() throws {
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: Data("""
        {
          "choices": [{"delta": {"content": "hi"}}],
          "x_groq": {
            "usage": {
              "prompt_tokens": 100,
              "completion_tokens": 20,
              "prompt_tokens_details": {"cached_tokens": 64}
            }
          }
        }
        """.utf8))
        let usage = chunk.x_groq?.usage
        XCTAssertEqual(usage?.prompt_tokens, 100)
        XCTAssertEqual(usage?.prompt_tokens_details?.cached_tokens, 64)
    }

    func testCachedAndReasoningTokenSpellingsDecode() throws {
        let openAI = try JSONDecoder().decode(OpenAIChunk.self, from: Data("""
        {
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5,
            "prompt_tokens_details": {"cached_tokens": 4},
            "completion_tokens_details": {"reasoning_tokens": 3}
          }
        }
        """.utf8))
        XCTAssertEqual(openAI.usage?.prompt_tokens_details?.cached_tokens, 4)
        XCTAssertEqual(openAI.usage?.completion_tokens_details?.reasoning_tokens, 3)

        let deepseek = try JSONDecoder().decode(OpenAIChunk.self, from: Data("""
        {"usage": {"prompt_tokens": 10, "prompt_cache_hit_tokens": 6}}
        """.utf8))
        XCTAssertEqual(deepseek.usage?.prompt_cache_hit_tokens, 6)
    }
}
