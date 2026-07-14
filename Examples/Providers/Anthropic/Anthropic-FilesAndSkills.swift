import AI
import Foundation

extension AnthropicExamples {
    static func filesAndSkills() async throws {
        let file = try await AnthropicFiles().upload(
            data: Data("Report".utf8),
            filename: "report.txt",
            mediaType: "text/plain"
        )
        print(file.id)

        let skill = try await AnthropicSkills().upload(
            files: [
                SkillFile(
                    path: "brand-guide/SKILL.md",
                    data: Data("# Brand guide\nUse clear, direct language.".utf8)
                )
            ],
            displayTitle: "Brand guide"
        )
        print(skill.id)
    }
}

