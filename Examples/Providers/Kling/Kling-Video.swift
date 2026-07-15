import AI

enum KlingExamples {
    static func textToVideo() async throws {
        let video = try await generateVideo(
            model: KlingVideoModel("kling-v2-master-t2v"),
            prompt: "A hot air balloon drifting over green hills",
            duration: 5
        )
        print(video.urls)
    }

    static func imageToVideo() async throws {
        let still = try exampleData(at: "/tmp/example.png")
        let video = try await generateVideo(
            model: KlingVideoModel("kling-v2-master-i2v"),
            prompt: "Slow parallax as clouds drift past",
            image: ImageContent(data: still, mediaType: "image/png")
        )
        print(video.urls)
    }
}
