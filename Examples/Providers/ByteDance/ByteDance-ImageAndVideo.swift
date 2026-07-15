import AI

enum ByteDanceExamples {
    static func seedreamImage() async throws {
        let result = try await generateImage(
            model: ByteDanceImageModel("seedream-4-0-250828"),
            prompt: "A koi pond at dusk, ink-wash style",
            size: "2048x2048"
        )
        print(result.image.count)
    }

    static func seedanceVideo() async throws {
        let video = try await generateVideo(
            model: ByteDanceVideoModel("seedance-1-0-pro-250528"),
            prompt: "The koi swim in a slow circle"
        )
        print(video.urls)
    }
}
