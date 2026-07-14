import AI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let myKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "sk-..."
let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "sk-..."
let groqKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? "gsk-..."

struct ExampleSummary: Codable, Sendable {
    var title: String
    var bullets: [String]
}

let exampleSummarySchema = Schema.object([
    "title": .string(description: "Short title"),
    "bullets": .array(of: .string(), minItems: 1)
])

struct OpenMeteoWeatherArguments: Decodable, Sendable {
    let city: String
}

private struct OpenMeteoGeocodingResponse: Decodable {
    struct Location: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }

    let results: [Location]?
}

private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature: Double
        let apparentTemperature: Double
        let relativeHumidity: Double
        let weatherCode: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Units: Decodable {
        let temperature: String
        let apparentTemperature: String
        let relativeHumidity: String
        let windSpeed: String

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case windSpeed = "wind_speed_10m"
        }
    }

    let timezone: String
    let current: Current
    let currentUnits: Units

    enum CodingKeys: String, CodingKey {
        case timezone, current
        case currentUnits = "current_units"
    }
}

enum OpenMeteoWeather {
    static func current(city: String) async throws -> JSONValue {
        let location = try await geocode(city: city)
        let forecast = try await forecast(
            latitude: location.latitude,
            longitude: location.longitude
        )
        let current = forecast.current
        let units = forecast.currentUnits
        let region = [location.name, location.admin1, location.country]
            .compactMap { $0 }
            .joined(separator: ", ")

        return .object([
            "location": .string(region),
            "latitude": .number(location.latitude),
            "longitude": .number(location.longitude),
            "condition": .string(condition(for: current.weatherCode)),
            "weatherCode": .number(Double(current.weatherCode)),
            "temperature": .number(current.temperature),
            "temperatureUnit": .string(units.temperature),
            "apparentTemperature": .number(current.apparentTemperature),
            "apparentTemperatureUnit": .string(units.apparentTemperature),
            "relativeHumidity": .number(current.relativeHumidity),
            "relativeHumidityUnit": .string(units.relativeHumidity),
            "windSpeed": .number(current.windSpeed),
            "windSpeedUnit": .string(units.windSpeed),
            "observedAt": .string(current.time),
            "timezone": .string(forecast.timezone),
            "source": .string("Open-Meteo"),
            "sourceURL": .string("https://open-meteo.com/")
        ])
    }

    private static func geocode(city: String) async throws -> OpenMeteoGeocodingResponse.Location {
        guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidRequest("A city is required")
        }
        var components = URLComponents(
            url: URL(string: "https://geocoding-api.open-meteo.com/v1/search")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        let response: OpenMeteoGeocodingResponse = try await request(components.url!)
        guard let location = response.results?.first else {
            throw AIError.invalidRequest("Open-Meteo could not find \"\(city)\"")
        }
        return location
    }

    private static func forecast(
        latitude: Double,
        longitude: Double
    ) async throws -> OpenMeteoForecastResponse {
        var components = URLComponents(
            url: URL(string: "https://api.open-meteo.com/v1/forecast")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return try await request(components.url!)
    }

    private static func request<Response: Decodable>(_ url: URL) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIError.decoding("Open-Meteo response: \(error)")
        }
    }

    private static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Rain showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Unknown"
        }
    }
}

func exampleWeatherTool() -> Tool {
    Tool.typed(
        name: "getWeather",
        description: "Get the current weather for a city from Open-Meteo.",
        parameters: [
            "type": "object",
            "properties": [
                "city": ["type": "string", "description": "City name"]
            ],
            "required": ["city"],
            "additionalProperties": false
        ]
    ) { (arguments: OpenMeteoWeatherArguments) in
        try await OpenMeteoWeather.current(city: arguments.city)
    }
}

func exampleData(at path: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path))
}
