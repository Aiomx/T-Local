import Foundation

public enum ScenarioCodec {
    public static let fileExtension = "telemetryscenario.json"

    public static func encode(_ scenario: TelemetryScenario) throws -> Data {
        try scenario.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(scenario)
    }

    public static func decode(_ data: Data) throws -> TelemetryScenario {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scenario = try decoder.decode(TelemetryScenario.self, from: data)
        try scenario.validate()
        return scenario
    }
}
