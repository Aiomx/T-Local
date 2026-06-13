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

public struct ScenarioLibraryFile: Equatable, Identifiable, Sendable {
    public var id: String { scenario.id }
    public var url: URL
    public var scenario: TelemetryScenario

    public init(url: URL, scenario: TelemetryScenario) {
        self.url = url
        self.scenario = scenario
    }
}

public enum ScenarioLibrary {
    public static func defaultDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("TelemetryScenarioStudio", isDirectory: true)
            .appendingPathComponent("Scenarios", isDirectory: true)
    }

    public static func loadScenarios(from directory: URL) throws -> [ScenarioLibraryFile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasSuffix(".\(ScenarioCodec.fileExtension)") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return try urls.map { url in
            let scenario = try ScenarioCodec.decode(try Data(contentsOf: url))
            return ScenarioLibraryFile(url: url, scenario: scenario)
        }
    }

    public static func write(_ scenario: TelemetryScenario, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: scenario, in: directory)
        try ScenarioCodec.encode(scenario).write(to: url, options: [.atomic])
        return url
    }

    public static func delete(_ scenario: TelemetryScenario, from directory: URL) throws {
        let url = fileURL(for: scenario, in: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func importedCopy(
        from scenario: TelemetryScenario,
        existingIDs: Set<String>,
        existingNames: Set<String>
    ) -> TelemetryScenario {
        var imported = scenario
        if existingIDs.contains(imported.id) {
            imported.id = UUID().uuidString
        }
        if existingNames.contains(imported.name) {
            imported.name += " Imported"
        }
        return imported
    }

    public static func fileURL(for scenario: TelemetryScenario, in directory: URL) -> URL {
        directory.appendingPathComponent("\(scenario.id).\(ScenarioCodec.fileExtension)")
    }

    public static func safeFileStem(for scenario: TelemetryScenario) -> String {
        let raw = "\(scenario.name)-\(scenario.id.prefix(8))"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? String(scenario.id.prefix(8)) : collapsed
    }
}
