import AI

enum QuiverAIExamples {
    static func generateSVG() async throws {
        let result = try await generateImage(
            model: QuiverAIImageModel("arrow-1.1"),
            prompt: "A minimalist mountain logo, single color"
        )
        let svg = String(decoding: result.image, as: UTF8.self)
        print(svg.prefix(64))
    }
}
