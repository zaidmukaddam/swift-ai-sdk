import AI

extension XAIExamples {
    static func textAndImageToVideo() async throws {
        let generated = try await generateVideo(
            model: XaiVideoModel("grok-imagine-video-1.5"),
            prompt: "A paper boat drifting down a rainy street",
            duration: 6
        )
        print(generated.urls)

        let still = try exampleData(at: "/tmp/example.png")
        let animated = try await generateVideo(
            model: XaiVideoModel("grok-imagine-video-1.5"),
            prompt: "Slow camera push-in",
            image: ImageContent(data: still, mediaType: "image/png")
        )
        print(animated.urls)
    }
}

