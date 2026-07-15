import AI

enum BlackForestLabsExamples {
    static func flux() async throws {
        let result = try await generateImage(
            model: BlackForestLabsImageModel("flux-pro-1.1"),
            prompt: "A tiny observatory on a snowy mountain at dusk",
            size: "1024x768"
        )
        print(result.image.count)
    }
}
