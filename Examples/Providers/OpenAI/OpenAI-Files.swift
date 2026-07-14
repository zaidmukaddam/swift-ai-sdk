import AI
import Foundation

extension OpenAIExamples {
    static func files() async throws {
        let file = try await OpenAIFiles().upload(
            data: Data("Reference notes".utf8),
            filename: "notes.txt",
            purpose: "user_data",
            mediaType: "text/plain"
        )
        print(file.id)
        try await OpenAIFiles().delete(id: file.id)
    }
}

