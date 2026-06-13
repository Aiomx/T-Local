import Foundation
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

@Test
func telemetryPreviewIncludesSimulationAndNetworkFields() throws {
    let node = VPNNode(
        id: "vpn-sg",
        displayName: "QA Singapore",
        regionCode: "SG",
        serverHost: "sg.vpn.internal",
        remoteIdentifier: "sg.vpn.internal",
        authentication: .usernamePassword(username: "qa", passwordReference: "keychain:vpn-sg")
    )
    var scenario = ScenarioTemplates.deliveryRoute
    scenario.networkProfile = NetworkProfile(
        name: "Singapore",
        regionCode: "SG",
        vpnNode: node,
        expectedCountryCode: "SG",
        dnsTestDomains: ["example.com"]
    )

    let preview = TelemetryEventPreview.scenarioPreview(
        scenario: scenario,
        ipResult: IPGeolocationResult(ipAddress: "203.0.113.10", countryCode: "SG"),
        dnsResult: DNSLeakResult(
            testedDomains: ["example.com"],
            expectedCountryCode: "SG",
            resolverSummaries: ["example.com:443"],
            leakDetected: false
        )
    )
    let fields = Dictionary(uniqueKeysWithValues: preview.payloadFields)

    #expect(fields["is_simulated"] == "true")
    #expect(fields["source"] == "qa_sdk")
    #expect(fields["scenario_id"] == scenario.id)
    #expect(fields["vpn_node_id"] == "vpn-sg")
    #expect(fields["public_ip"] == "203.0.113.10")
    #expect(fields["ip_country"] == "SG")
    #expect(fields["dns_leak_detected"] == "false")
}

@Test
func telemetryPreviewJSONIncludesRouteAndAccuracyFields() throws {
    let scenario = TelemetryScenario(
        id: "scenario-json",
        name: "Payload Preview",
        route: [
            RoutePoint(
                latitude: 31.2,
                longitude: 121.4,
                altitude: 16,
                horizontalAccuracy: 4,
                verticalAccuracy: 7,
                speed: 8,
                course: 92,
                elapsedSeconds: 30,
                label: "Start"
            )
        ],
        expectedTelemetryTags: ["qa": "true"]
    )

    let preview = TelemetryEventPreview.scenarioPreview(
        scenario: scenario,
        routePoint: scenario.route[0],
        routePointIndex: 0,
        routeElapsedSeconds: 30
    )
    let json = preview.prettyPrintedJSONString

    #expect(json.contains(#""is_simulated" : true"#))
    #expect(json.contains(#""scenario_id" : "scenario-json""#))
    #expect(json.contains(#""scenario_name" : "Payload Preview""#))
    #expect(json.contains(#""horizontal_accuracy" : 4"#))
    #expect(json.contains(#""route_point_index" : 0"#))
    #expect(json.contains(#""tags" : {"#))
}

@Test
func routeMetricsAndEndpointSwapAreStable() throws {
    let scenario = TelemetryScenario(
        id: "route-metrics",
        name: "Route Metrics",
        route: [
            RoutePoint(latitude: 0, longitude: 0, speed: 0, elapsedSeconds: 0, dwellSeconds: 5, label: "Start"),
            RoutePoint(latitude: 0, longitude: 0.001, speed: 10, elapsedSeconds: 20, dwellSeconds: 7, label: "End")
        ]
    )

    let metrics = scenario.routeMetrics
    #expect(metrics.pointCount == 2)
    #expect(metrics.totalDistanceMeters > 100)
    #expect(metrics.totalDurationSeconds == 27)
    #expect(metrics.totalDwellSeconds == 12)
    #expect(metrics.averageSpeedMetersPerSecond > 3)

    let reversed = scenario.reversedRoutePreservingTiming()
    #expect(reversed.id == scenario.id)
    #expect(reversed.route.count == 2)
    #expect(reversed.route[0].latitude == scenario.route[1].latitude)
    #expect(reversed.route[0].elapsedSeconds == 0)
    #expect(reversed.route[1].elapsedSeconds == 20)
}

@Test
func scenarioLibraryRoundTripsFilesAndImportsDuplicateIDs() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TelemetryScenarioLibraryTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let scenario = ScenarioTemplates.cityNavigation
    let url = try ScenarioLibrary.write(scenario, to: directory)
    let loaded = try ScenarioLibrary.loadScenarios(from: directory)

    #expect(url.lastPathComponent.hasSuffix(".telemetryscenario.json"))
    #expect(loaded.count == 1)
    #expect(loaded.first?.scenario.id == scenario.id)

    let imported = ScenarioLibrary.importedCopy(
        from: scenario,
        existingIDs: [scenario.id],
        existingNames: [scenario.name]
    )

    #expect(imported.id != scenario.id)
    #expect(imported.name.contains("Imported"))
}

@Test
func scenarioSearchMatchesNameDescriptionTagsAndPointLabels() throws {
    let scenario = TelemetryScenario(
        name: "Cross Border",
        description: "handoff scenario",
        route: [
            RoutePoint(latitude: 22.5431, longitude: 114.0579, elapsedSeconds: 0, label: "Shenzhen"),
            RoutePoint(latitude: 22.3193, longitude: 114.1694, elapsedSeconds: 600, label: "Hong Kong")
        ],
        expectedTelemetryTags: ["template": "border", "qa": "true"]
    )

    #expect(scenario.matchesSearchText("border"))
    #expect(scenario.matchesSearchText("handoff"))
    #expect(scenario.matchesSearchText("Hong Kong"))
    #expect(scenario.hasTag("template"))
    #expect(!scenario.matchesSearchText("airport"))
}
