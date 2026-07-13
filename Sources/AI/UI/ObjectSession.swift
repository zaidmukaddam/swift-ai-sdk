#if canImport(Observation)
import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ObjectTransport: Sendable {
    func stream(input: JSONValue) async throws -> AsyncThrowingStream<String, Error>
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable @MainActor
public final class ObjectSession {
    public enum Status: Sendable, Equatable {
        case ready
        case loading
        case error(String)
    }

    public private(set) var object: JSONValue?
    public private(set) var status: Status = .ready
    public var isLoading: Bool { status == .loading }

    private let transport: any ObjectTransport
    private var task: Task<Void, Never>?

    public init(transport: any ObjectTransport) {
        self.transport = transport
    }

    public init(
        model: any LanguageModel,
        schema: Schema,
        system: String? = nil,
        maxOutputTokens: Int = 1024,
        temperature: Double? = nil
    ) {
        self.transport = LocalObjectTransport(
            model: model, schema: schema.jsonSchema, system: system,
            maxOutputTokens: maxOutputTokens, temperature: temperature
        )
    }

    public func submit(_ input: JSONValue) {
        task?.cancel()
        object = nil
        status = .loading

        task = Task { [transport] in
            do {
                var buffer = ""
                let deltas = try await transport.stream(input: input)
                for try await delta in deltas {
                    if Task.isCancelled { break }
                    buffer += delta
                    if let partial = PartialJSON.parse(buffer), partial != object {
                        object = partial
                    }
                }
                if !Task.isCancelled { status = .ready }
            } catch is CancellationError {
                status = .ready
            } catch {
                status = .error("\(error)")
            }
        }
    }

    public func decoded<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let object else { return nil }
        return try? object.decode(T.self)
    }

    public func stop() {
        task?.cancel()
        task = nil
        if isLoading { status = .ready }
    }

    public func clear() {
        stop()
        object = nil
        status = .ready
    }
}

public struct HTTPObjectTransport: ObjectTransport {
    public var api: URL
    public var headers: [String: String]
    private let urlSession: URLSession

    public init(
        api: URL,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.api = api
        self.headers = headers
        self.urlSession = urlSession
    }

    public func stream(input: JSONValue) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: api)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(input)

        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw AIError.http(status: http.statusCode, body: errorBody)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var pending = Data()
                    for try await byte in bytes {
                        pending.append(byte)
                        if let (text, remainder) = Self.decodeCompletePrefix(pending) {
                            if !text.isEmpty { continuation.yield(text) }
                            pending = remainder
                        }
                    }
                    if !pending.isEmpty {
                        continuation.yield(String(decoding: pending, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func decodeCompletePrefix(_ data: Data) -> (String, Data)? {
        for holdBack in 0...min(3, data.count) {
            let cut = data.count - holdBack
            let prefix = data.prefix(cut)
            if let text = String(bytes: prefix, encoding: .utf8) {
                return (text, Data(data.suffix(holdBack)))
            }
        }
        return nil
    }
}

struct LocalObjectTransport: ObjectTransport {
    var model: any LanguageModel
    var schema: JSONValue
    var system: String?
    var maxOutputTokens: Int
    var temperature: Double?

    func stream(input: JSONValue) async throws -> AsyncThrowingStream<String, Error> {
        let prompt = input.stringValue ?? {
            let data = (try? JSONEncoder().encode(input)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }()
        let request = LanguageModelRequest(
            messages: assembleMessages(messages: [], system: system, prompt: prompt),
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            responseFormat: .json(schema: schema)
        )
        let parts = try await model.stream(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await part in parts {
                        switch part {
                        case .textDelta(let delta):
                            continuation.yield(delta)
                        case .toolArgumentsDelta(_, let fragment):
                            continuation.yield(fragment)
                        default:
                            break
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
#endif
