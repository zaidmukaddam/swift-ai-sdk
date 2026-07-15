import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MCPSSETransport: MCPTransport {
    private let sseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let requestTimeout: TimeInterval

    private var started = false
    private var closed = false
    private var messageEndpoint: URL?
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var endpointWaiters: [CheckedContinuation<URL, Error>] = []
    private var readerTask: Task<Void, Never>?

    public init(
        url: URL,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 60
    ) {
        self.sseURL = url
        self.headers = headers
        self.urlSession = urlSession
        self.requestTimeout = requestTimeout
    }

    public func request(id: Int, method: String, params: JSONValue) async throws -> JSONValue {
        start()
        let endpoint = try await awaitEndpoint()
        let body: JSONValue = .object([
            "jsonrpc": "2.0",
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            armTimeout(for: id)
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.post(body: body, to: endpoint)
                } catch {
                    await self.failPending(id: id, error: error)
                }
            }
        }
    }

    public func notify(method: String) async throws {
        start()
        let endpoint = try await awaitEndpoint()
        try await post(body: .object([
            "jsonrpc": "2.0",
            "method": .string(method)
        ]), to: endpoint)
    }

    public func close() {
        guard !closed else { return }
        closed = true
        readerTask?.cancel()
        failAllPending(AIError.transport("MCP SSE transport closed"))
        for waiter in endpointWaiters {
            waiter.resume(throwing: AIError.transport("MCP SSE transport closed"))
        }
        endpointWaiters.removeAll()
    }

    private func start() {
        guard !started, !closed else { return }
        started = true
        readerTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        do {
            var request = URLRequest(url: sseURL)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
            let (bytes, response) = try await urlSession.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AIError.http(status: http.statusCode, body: "MCP SSE stream refused")
            }
            for try await event in SSE.events(from: bytes) {
                handleEvent(event)
            }
            failAllPending(AIError.transport("MCP SSE stream ended"))
        } catch {
            failEndpointWaiters(error)
            failAllPending(error)
        }
    }

    private func handleEvent(_ event: SSEEvent) {
        if event.event == "endpoint" {
            let raw = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = URL(string: raw, relativeTo: sseURL)?.absoluteURL
                ?? URL(string: raw)
            guard let endpoint = resolved else { return }
            messageEndpoint = endpoint
            let waiters = endpointWaiters
            endpointWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: endpoint) }
            return
        }
        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
        else { return }
        if payload["method"] != nil { return }
        guard let id = payload["id"]?.intValue,
              let continuation = pending.removeValue(forKey: id)
        else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: payload)
    }

    private func awaitEndpoint() async throws -> URL {
        if let messageEndpoint { return messageEndpoint }
        if closed { throw AIError.transport("MCP SSE transport closed") }
        return try await withCheckedThrowingContinuation { continuation in
            endpointWaiters.append(continuation)
        }
    }

    private func post(body: JSONValue, to endpoint: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.transport("MCP SSE post got a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
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
            "MCP SSE request \(id) timed out after \(requestTimeout)s"
        ))
    }

    private func failPending(id: Int, error: Error) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        for (_, task) in timeouts { task.cancel() }
        timeouts.removeAll()
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    private func failEndpointWaiters(_ error: Error) {
        let waiters = endpointWaiters
        endpointWaiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }
}
