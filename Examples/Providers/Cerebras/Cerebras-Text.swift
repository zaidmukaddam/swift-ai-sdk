import AI

enum CerebrasExamples {
    static func text() async throws {
        let result = streamText(
            model: CerebrasModel("gpt-oss-120b"),
            prompt: "Give me three practical Swift performance tips."
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
