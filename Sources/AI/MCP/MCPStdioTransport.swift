import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(macOS) || os(Linux)
public actor MCPStdioTransport: MCPTransport {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private let workingDirectory: String?
    private let requestTimeout: TimeInterval

    private var started = false
    private var closed = false
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var readerTask: Task<Void, Never>?

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        requestTimeout: TimeInterval = 60
    ) {
        self.command = command
        self.arguments = arguments
        var merged = ProcessInfo.processInfo.environment
        if let environment { for (key, value) in environment { merged[key] = value } }
        self.environment = merged
        self.workingDirectory = workingDirectory
        self.requestTimeout = requestTimeout
    }

    public func request(id: Int, method: String, params: JSONValue) async throws -> JSONValue {
        try start()
        let body: JSONValue = .object([
            "jsonrpc": "2.0",
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try writeLine(body)
                armTimeout(for: id)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func armTimeout(for id: Int) {
        let seconds = requestTimeout
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.fireTimeout(id)
        }
    }

    private func fireTimeout(_ id: Int) {
        timeouts[id] = nil
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: AIError.transport(
            "MCP stdio request \(id) timed out after \(requestTimeout)s"
        ))
    }

    public func notify(method: String) async throws {
        try start()
        try writeLine(.object([
            "jsonrpc": "2.0",
            "method": .string(method)
        ]))
    }

    public func close() {
        guard !closed else { return }
        closed = true
        readerTask?.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if started && process.isRunning { process.terminate() }
        failAllPending(AIError.transport("MCP stdio transport closed"))
    }

    private func start() throws {
        guard !started else { return }
        guard !closed else { throw AIError.transport("MCP stdio transport already closed") }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        do {
            try process.run()
        } catch {
            throw AIError.transport("MCP stdio failed to launch \(command): \(error)")
        }
        started = true
        startReader()
    }

    private func startReader() {
        let handle = stdoutPipe.fileHandleForReading
        let stream = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { fileHandle in
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
        readerTask = Task { [weak self] in
            for await chunk in stream {
                await self?.ingest(chunk)
            }
            await self?.failAllPending(AIError.transport("MCP stdio server closed the stream"))
        }
    }

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let payload = try? JSONDecoder().decode(JSONValue.self, from: line)
        else { return }
        if payload["method"] != nil { return }
        guard let id = payload["id"]?.intValue,
              let continuation = pending.removeValue(forKey: id)
        else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: payload)
    }

    private func failAllPending(_ error: Error) {
        for (_, task) in timeouts { task.cancel() }
        timeouts.removeAll()
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    private func writeLine(_ body: JSONValue) throws {
        var data = try JSONEncoder().encode(body)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }
}
#endif
