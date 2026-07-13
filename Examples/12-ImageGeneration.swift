import AI
import Foundation

func example_generateImage() async throws {
    let result = try await generateImage(
        model: OpenAIImageModel("gpt-image-1"),
        prompt: "A watercolor fox in a snowy forest",
        size: "1024x1024"
    )
    let output = URL(fileURLWithPath: "/tmp/fox.png")
    try result.image.write(to: output)
    print("wrote", output.path)
}
