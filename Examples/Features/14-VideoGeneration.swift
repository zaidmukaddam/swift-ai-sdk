import AI
import Foundation

func example_generateVideo() async throws {
    let result = try await generateVideo(
        model: XaiVideoModel("grok-imagine-video-1.5"),
        prompt: "A paper boat drifting down a rainy street, cinematic",
        duration: 6
    )
    print("finished:", result.urls.first?.absoluteString ?? "no url")
}

func example_imageToVideo() async throws {
    let still = try Data(contentsOf: URL(fileURLWithPath: "/tmp/fox.png"))
    let result = try await generateVideo(
        model: XaiVideoModel("grok-imagine-video-1.5"),
        prompt: "The fox blinks and snow falls gently",
        image: ImageContent(data: still)
    )
    print(result.urls)
}
