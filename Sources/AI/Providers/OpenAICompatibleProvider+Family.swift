import Foundation

public extension OpenAICompatibleProvider {
    private static func preset(
        _ name: String, _ url: String, _ apiKey: String?, _ envVar: String
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            name: name,
            baseURL: URL(string: url)!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment[envVar]
        )
    }

    static func deepInfra(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("deepinfra", "https://api.deepinfra.com/v1/openai", apiKey, "DEEPINFRA_API_KEY")
    }

    static func baseten(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("baseten", "https://inference.baseten.co/v1", apiKey, "BASETEN_API_KEY")
    }

    static func vercel(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("vercel", "https://api.v0.dev/v1", apiKey, "VERCEL_API_KEY")
    }

    static func gateway(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("gateway", "https://ai-gateway.vercel.sh/v1", apiKey, "AI_GATEWAY_API_KEY")
    }

    static func sarvam(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("sarvam", "https://api.sarvam.ai/v1", apiKey, "SARVAM_API_KEY")
    }
}
