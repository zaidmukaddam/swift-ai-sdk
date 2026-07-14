import AI

func example_approvals() async throws {
    let deleteFile = Tool(
        name: "deleteFile", description: "Removes a file from disk",
        parameters: ["type": "object",
                     "properties": ["path": ["type": "string"]],
                     "required": ["path"]],
        needsApproval: true
    ) { args in
        .string("deleted \(args["path"]?.stringValue ?? "?")")
    }

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "Clean up /tmp/scratch.txt",
        tools: [deleteFile]
    )

    for request in result.steps.last?.approvalRequests ?? [] {
        print("wants to run \(request.call.name) with \(request.call.arguments)")
        var messages = result.messages
        messages.append(Message(role: .tool, content: [
            .toolApprovalResponse(ToolApprovalResponse(
                approvalID: request.approvalID,
                toolCallID: request.call.id,
                approved: true
            ))
        ]))
        let resumed = try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            messages: messages,
            tools: [deleteFile]
        )
        print(resumed.text)
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_approvalsInChat(chat: ChatSession) {
    for part in chat.messages.last?.parts ?? [] {
        guard case .tool(let tool) = part, tool.state == .approvalRequested,
              let approval = tool.approval else { continue }
        chat.addToolApprovalResponse(approvalID: approval.id, approved: true)
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
func example_clientSideTool(chat: ChatSession) {
    for part in chat.messages.last?.parts ?? [] {
        guard case .tool(let tool) = part, tool.state == .inputAvailable,
              tool.toolName == "pickPhoto" else { continue }
        chat.addToolResult(toolCallID: tool.toolCallID, result: ["photoID": "IMG_0042"])
    }
}
