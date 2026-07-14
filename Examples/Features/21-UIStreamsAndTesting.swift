import AI
import Foundation

func example_buildUIStream() -> AsyncThrowingStream<UIMessageChunk, Error> {
    UIMessageStream.build { writer in
        writer.write(.data(name: "data-status", data: .string("looking things up")))

        let result = streamText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: "Say hello."
        )
        writer.merge(UIMessageStream.chunks(from: result.fullStream))
    }
}

func example_messageMetadata() -> AsyncThrowingStream<UIMessageChunk, Error> {
    let result = streamText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "Say hello."
    )
    return UIMessageStream.chunks(
        from: result.fullStream,
        metadata: .object(["model": .string("claude-sonnet-5")]),
        messageMetadata: { part in
            if case .finish(_, let usage) = part {
                return .object(["totalTokens": .number(Double(usage.totalTokens))])
            }
            return nil
        }
    )
}

func example_readUIStream(chunks: AsyncThrowingStream<UIMessageChunk, Error>) async throws {
    for try await snapshot in readUIMessageStream(chunks) {
        print(snapshot.text)
    }
}
