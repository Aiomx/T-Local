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
