import AI
import Foundation

func example_mcpHTTP() async throws {
    let mcp = MCPClient(transport: MCPHTTPTransport(
        url: URL(string: "https://mcp.deepwiki.com/mcp")!
    ))
    try await mcp.connect()
    defer { Task { await mcp.close() } }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "Use the DeepWiki tools to explain how the modelcontextprotocol/modelcontextprotocol repository is organized.",
        tools: try await mcp.tools(),
        stopWhen: [stepCountIs(5)]
    )
    print(result.text)
}

func example_mcpDeepWikiDirect() async throws {
    let mcp = MCPClient(transport: MCPHTTPTransport(
        url: URL(string: "https://mcp.deepwiki.com/mcp")!
    ))
    try await mcp.connect()
    defer { Task { await mcp.close() } }

    let tools = try await mcp.tools()
    print("DeepWiki tools: \(tools.map(\.name))")

    let structure = try await mcp.callTool(
        name: "read_wiki_structure",
        arguments: ["repoName": "modelcontextprotocol/modelcontextprotocol"]
    )
    print(structure.stringValue ?? "\(structure)")
}

#if os(macOS) || os(Linux)
func example_mcpStdio() async throws {
    let mcp = MCPClient(transport: MCPStdioTransport(
        command: "npx",
        arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
        requestTimeout: 30
    ))
    try await mcp.connect()
    defer { Task { await mcp.close() } }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "List the files in /tmp and summarize what you find.",
        tools: try await mcp.tools(),
        stopWhen: [stepCountIs(5)]
    )
    print(result.text)
}
#endif

func example_mcpLegacySSE() async throws {
    let mcp = MCPClient(transport: MCPSSETransport(
        url: URL(string: "https://legacy.example.com/sse")!
    ))
    try await mcp.connect()
    defer { Task { await mcp.close() } }

    let tools = try await mcp.tools()
    print("discovered \(tools.count) tools: \(tools.map(\.name))")
}

func example_mcpRugPullDetection() async throws {
    let mcp = MCPClient(transport: MCPHTTPTransport(
        url: URL(string: "https://mcp.deepwiki.com/mcp")!
    ))
    try await mcp.connect()
    defer { Task { await mcp.close() } }

    let approved = fingerprintTools(try await mcp.tools())

    let latest = try await mcp.tools()
    let drift = detectToolDrift(fingerprintTools(latest), baseline: approved)
    guard !drift.hasDrift else {
        print("tool definitions drifted - changed: \(drift.changed), added: \(drift.added)")
        return
    }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "Ask DeepWiki what the modelcontextprotocol/modelcontextprotocol repository documents about transports.",
        tools: latest,
        stopWhen: [stepCountIs(5)]
    )
    print(result.text)
}
