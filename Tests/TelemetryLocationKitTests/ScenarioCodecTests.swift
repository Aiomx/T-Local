import Testing
@testable import TelemetryLocationKit

@Test
func scenarioRoundTripsThroughJSON() throws {
    let scenario = ScenarioTemplates.deliveryRoute

    let data = try ScenarioCodec.encode(scenario)
    let decoded = try ScenarioCodec.decode(data)

    #expect(decoded.name == scenario.name)
    #expect(decoded.route.count == scenario.route.count)
    #expect(decoded.expectedTelemetryTags["is_simulated"] == "true")
}

@Test
func gpxExporterIncludesWaypointsAndTrack() throws {
    let scenario = ScenarioTemplates.fitnessRun

    let gpx = try GPXExporter.export(scenario)

    #expect(gpx.contains("<gpx"))
    #expect(gpx.contains("<wpt lat="))
    #expect(gpx.contains("<trkpt lat="))
    #expect(gpx.contains("Fitness Run"))
}
