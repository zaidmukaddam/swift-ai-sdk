#if canImport(Observation)
import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol CompletionTransport: Sendable {
    func complete(prompt: String) async throws -> AsyncThrowingStream<String, Error>
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable @MainActor
public final class CompletionSession {
    public enum Status: Sendable, Equatable {
        case ready
        case loading
        case error(String)
    }

    public private(set) var completion = ""
    public private(set) var status: Status = .ready
    public var isLoading: Bool { status == .loading }

    private let transport: any CompletionTransport
    private var task: Task<Void, Never>?

    public init(transport: any CompletionTransport) {
        self.transport = transport
    }

    public init(
        model: any LanguageModel,
        system: String? = nil,
        maxOutputTokens: Int = 1024,
        temperature: Double? = nil
    ) {
        self.transport = LocalCompletionTransport(
            model: model, system: system,
            maxOutputTokens: maxOutputTokens, temperature: temperature
        )
    }

    public func complete(_ prompt: String) {
        task?.cancel()
        completion = ""
        status = .loading

        task = Task { [transport] in
            do {
                let deltas = try await transport.complete(prompt: prompt)
                for try await delta in deltas {
                    if Task.isCancelled { break }
                    completion += delta
                }
                if !Task.isCancelled { status = .ready }
            } catch is CancellationError {
                status = .ready
            } catch {
                status = .error("\(error)")
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if isLoading { status = .ready }
    }
}

public struct HTTPCompletionTransport: CompletionTransport {
    public var api: URL
    public var headers: [String: String]
    public var body: JSONValue?
    private let urlSession: URLSession

    public init(
        api: URL,
        headers: [String: String] = [:],
        body: JSONValue? = nil,
        urlSession: URLSession = .shared
    ) {
        self.api = api
        self.headers = headers
        self.body = body
        self.urlSession = urlSession
    }

    public func complete(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: api)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        var payload: [String: JSONValue] = [:]
        if case .object(let extra)? = body {
            for (key, value) in extra { payload[key] = value }
        }
        payload["prompt"] = .string(prompt)
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(payload))

        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw AIError.http(status: http.statusCode, body: errorBody)
        }

        let chunks = HTTPChatTransport.chunkStream(from: bytes)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        if case .textDelta(_, let delta) = chunk {
                            continuation.yield(delta)
                        }
                        if case .error(let errorText) = chunk {
                            throw AIError.transport(errorText)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct LocalCompletionTransport: CompletionTransport {
    var model: any LanguageModel
    var system: String?
    var maxOutputTokens: Int
    var temperature: Double?

    func complete(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        streamText(
            model: model, system: system, prompt: prompt,
            maxOutputTokens: maxOutputTokens, temperature: temperature
        ).textStream
    }
}
#endif
