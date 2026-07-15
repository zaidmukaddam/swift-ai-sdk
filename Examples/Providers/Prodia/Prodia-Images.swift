import AI

enum ProdiaExamples {
    static func flux() async throws {
        let result = try await generateImage(
            model: ProdiaImageModel("inference.flux.schnell.txt2img.v2"),
            prompt: "A neon city street in the rain"
        )
        print(result.image.count)
    }
}
