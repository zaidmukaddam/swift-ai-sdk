import AI

extension LumaExamples {
    static func textAndImageToVideo() async throws {
        let generated = try await generateVideo(
            model: LumaVideoModel("ray-2"),
            prompt: "A tram crossing a rainy neon street",
            aspectRatio: "16:9",
            duration: 5
        )
        print(generated.urls)

        let still = try exampleData(at: "/tmp/luma-image.png")
        let animated = try await generateVideo(
            model: LumaVideoModel("ray-flash-2"),
            prompt: "Slow camera push-in",
            image: ImageContent(data: still, mediaType: "image/png")
        )
        print(animated.urls)
    }
}

