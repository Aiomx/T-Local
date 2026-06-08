import Foundation

public enum GPXExporter {
    public static func export(_ scenario: TelemetryScenario) throws -> String {
        try scenario.validate()
        let waypoints = scenario.route.map { point in
            let name = xmlEscaped(point.label ?? "Point \(Int(point.elapsedSeconds))s")
            return """
              <wpt lat="\(point.latitude)" lon="\(point.longitude)">
                <ele>\(point.altitude)</ele>
                <name>\(name)</name>
              </wpt>
            """
        }.joined(separator: "\n")

        let trackPoints = scenario.route.map { point in
            """
                <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                  <ele>\(point.altitude)</ele>
                  <time>\(iso8601Time(offset: point.elapsedSeconds))</time>
                </trkpt>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Telemetry Scenario Studio" xmlns="http://www.topografix.com/GPX/1/1">
        \(waypoints)
          <trk>
            <name>\(xmlEscaped(scenario.name))</name>
            <trkseg>
        \(trackPoints)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    private static func iso8601Time(offset: TimeInterval) -> String {
        let base = Date(timeIntervalSince1970: 1_704_067_200)
        return ISO8601DateFormatter().string(from: base.addingTimeInterval(offset))
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
