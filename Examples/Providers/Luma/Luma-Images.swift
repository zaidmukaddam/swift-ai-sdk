import AI
import Foundation

enum LumaExamples {
    static func images() async throws {
        let result = try await generateImage(
            model: LumaImageModel("photon-1"),
            prompt: "Editorial product photography on red paper",
            aspectRatio: "4:3"
        )
        try result.image.write(to: URL(fileURLWithPath: "/tmp/luma-image.png"))
    }
}

