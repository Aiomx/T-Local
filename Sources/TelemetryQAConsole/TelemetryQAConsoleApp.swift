import CoreLocation
import SwiftUI
import TelemetryLocationKit

@main
struct TelemetryQAConsoleApp: App {
    @State private var store = QAConsoleStore()

    var body: some Scene {
        WindowGroup {
            QAConsoleView(store: store)
        }
    }
}

@MainActor
@Observable
final class QAConsoleStore {
    var scenarios: [TelemetryScenario] = ScenarioTemplates.all
    var selectedScenarioID: String?
    var playbackSpeed: Double = 1
    var currentLocation: CLLocation?
    var playbackState = "Idle"
    var telemetryEvents: [TelemetryEvent] = []
    var importText = ""
    var diagnosticsText = ""
    var vpnStatusText = "Disconnected"
    var vpnCredentialSecret = ""
    var vpnCredentialReferenceText = "qa-vpn"
    var vpnDisplayNameText = "QA VPN"
    var vpnRegionText = "US"
    var vpnServerHostText = ""
    var vpnRemoteIdentifierText = ""
    var vpnLocalIdentifierText = ""
    var vpnUsernameText = "qa"
    var vpnLatencyEndpointText = "https://www.apple.com/library/test/success.html"
    var vpnIPEndpointText = "https://api.ipify.org?format=json"
    var vpnDNSDomainsText = "example.com, apple.com"
    var vpnExpectedCountryText = ""
    var latencyResult: LatencyResult?
    var ipGeolocationResult: IPGeolocationResult?
    var dnsLeakResult: DNSLeakResult?
    var isRunningDiagnostics = false
    var errorMessage: String?

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private let eventSink = InMemoryTelemetryEventSink()
    @ObservationIgnored private let diagnostics: NetworkDiagnosticsClient = URLSessionNetworkDiagnosticsClient()
    @ObservationIgnored private let vpnService = PersonalVPNService()

    var selectedScenario: TelemetryScenario {
        scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
    }

    var currentVPNNode: VPNNode? {
        guard !vpnServerHostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return selectedScenario.networkProfile?.vpnNode
        }
        return editableVPNNode
    }

    var editableVPNNode: VPNNode {
        VPNNode(
            displayName: emptyFallback(vpnDisplayNameText, fallback: "QA VPN"),
            regionCode: emptyFallback(vpnRegionText, fallback: "QA"),
            serverHost: vpnServerHostText.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteIdentifier: emptyFallback(vpnRemoteIdentifierText, fallback: vpnServerHostText),
            localIdentifier: vpnLocalIdentifierText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            authentication: .usernamePassword(
                username: emptyFallback(vpnUsernameText, fallback: "qa"),
                passwordReference: "keychain:\(emptyFallback(vpnCredentialReferenceText, fallback: "qa-vpn"))"
            ),
            dnsServers: [],
            healthCheckURL: URL(string: vpnLatencyEndpointText)
        )
    }

    var telemetryPreview: TelemetryEventPreview {
        TelemetryEventPreview.scenarioPreview(
            scenario: selectedScenario,
            location: currentLocation,
            ipResult: ipGeolocationResult,
            dnsResult: dnsLeakResult
        )
    }

    init() {
        selectedScenarioID = scenarios.first?.id
        applyScenarioNetworkProfile()
    }

    func selectScenario(_ id: String?) {
        selectedScenarioID = id
        applyScenarioNetworkProfile()
    }

    func startPlayback() {
        playbackTask?.cancel()
        playbackState = "Playing"
        let scenario = selectedScenario
        let provider = MockRouteLocationProvider(scenario: scenario, playbackSpeed: playbackSpeed)

        playbackTask = Task {
            do {
                for try await location in provider.locations() {
                    currentLocation = location
                    let event = TelemetryEvent(
                        scenarioID: scenario.id,
                        source: "qa_sdk",
                        isSimulated: true,
                        location: location,
                        vpnNodeID: currentVPNNode?.id ?? scenario.networkProfile?.vpnNode?.id,
                        ipCountryCode: ipGeolocationResult?.countryCode,
                        dnsLeakDetected: dnsLeakResult?.leakDetected,
                        tags: scenario.expectedTelemetryTags
                    )
                    try await eventSink.record(event)
                    telemetryEvents = await eventSink.events()
                }
                playbackState = "Finished"
            } catch {
                errorMessage = error.localizedDescription
                playbackState = "Failed"
            }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackState = "Stopped"
    }

    func importScenario() {
        do {
            let scenario = try ScenarioCodec.decode(Data(importText.utf8))
            scenarios.append(scenario)
            selectedScenarioID = scenario.id
            applyScenarioNetworkProfile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveVPNSecret() {
        do {
            try VPNCredentialStore.savePassword(
                vpnCredentialSecret,
                reference: "keychain:\(emptyFallback(vpnCredentialReferenceText, fallback: "qa-vpn"))"
            )
            vpnCredentialSecret = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configureVPN() async {
        let node = editableVPNNode
        guard !node.serverHost.isEmpty else {
            errorMessage = "Enter a VPN server host first."
            return
        }
        await vpnService.configure(node: node)
        vpnStatusText = vpnService.statusText
        errorMessage = vpnService.lastError
    }

    func connectVPN() async {
        await configureVPN()
        guard vpnService.lastError == nil else {
            return
        }
        vpnService.connect()
        vpnStatusText = vpnService.statusText
        errorMessage = vpnService.lastError
    }

    func disconnectVPN() {
        vpnService.disconnect()
        vpnStatusText = vpnService.statusText
    }

    func runDiagnostics() {
        let scenario = selectedScenario
        Task {
            await runDiagnosticsAsync(scenario: scenario)
        }
    }

    private func runDiagnosticsAsync(scenario: TelemetryScenario) async {
        guard let ipURL = URL(string: vpnIPEndpointText) else {
            errorMessage = "Enter a valid IP endpoint."
            return
        }

        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        do {
            var lines: [String] = ["Target device network diagnostics"]
            if let url = URL(string: vpnLatencyEndpointText) ?? scenario.networkProfile?.vpnNode?.healthCheckURL {
                let latency = try await diagnostics.measureLatency(to: url)
                latencyResult = latency
                lines.append("Latency: \(Int(latency.milliseconds)) ms (\(latency.statusCode ?? 0))")
            }

            let ip = try await diagnostics.fetchIPGeolocation(from: ipURL)
            ipGeolocationResult = ip
            lines.append("Public IP: \(ip.ipAddress)")
            if let country = ip.countryCode {
                lines.append("Country: \(country)")
            }

            let domains = vpnDNSDomainsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let expectedCountry = vpnExpectedCountryText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? scenario.networkProfile?.expectedCountryCode
            let dns = try await diagnostics.checkDNSLeak(
                domains: domains.isEmpty ? (scenario.networkProfile?.dnsTestDomains ?? ["example.com"]) : domains,
                expectedCountryCode: expectedCountry
            )
            dnsLeakResult = dns
            lines.append("DNS leak detected: \(dns.leakDetected ? "yes" : "no")")
            diagnosticsText = lines.joined(separator: "\n")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyScenarioNetworkProfile() {
        guard let profile = selectedScenario.networkProfile else {
            return
        }
        vpnRegionText = profile.expectedCountryCode ?? profile.regionCode
        vpnExpectedCountryText = profile.expectedCountryCode ?? ""
        vpnDNSDomainsText = profile.dnsTestDomains.joined(separator: ", ")
        guard let node = profile.vpnNode else {
            return
        }
        vpnDisplayNameText = node.displayName
        vpnRegionText = node.regionCode
        vpnServerHostText = node.serverHost
        vpnRemoteIdentifierText = node.remoteIdentifier
        vpnLocalIdentifierText = node.localIdentifier ?? ""
        vpnLatencyEndpointText = node.healthCheckURL?.absoluteString ?? vpnLatencyEndpointText
        switch node.authentication {
        case let .usernamePassword(username, passwordReference):
            vpnUsernameText = username
            vpnCredentialReferenceText = VPNCredentialStore.normalizedReference(passwordReference)
        case .certificate:
            break
        }
    }

    private func emptyFallback(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct QAConsoleView: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedScenarioID) {
                ForEach(store.scenarios) { scenario in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.name)
                            .font(.headline)
                        Text(scenario.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(scenario.id))
                }
            }
            .navigationTitle("QA Console")
            .onChange(of: store.selectedScenarioID) { _, newValue in
                store.selectScenario(newValue)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Header(store: store)
                    CurrentLocationPanel(location: store.currentLocation, state: store.playbackState)
                    TargetVPNPanel(store: store)
                    DiagnosticsPanel(store: store)
                    TelemetryPreviewPanel(preview: store.telemetryPreview)
                    ImportScenarioPanel(store: store)
                    TelemetryEventsPanel(events: store.telemetryEvents)
                }
                .padding(20)
            }
        }
    }
}

struct Header: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.selectedScenario.name)
                .font(.largeTitle.bold())
            Text(store.selectedScenario.description)
                .foregroundStyle(.secondary)
            HStack {
                Button("Play") { store.startPlayback() }
                Button("Stop") { store.stopPlayback() }
                Slider(value: $store.playbackSpeed, in: 0.25...8)
                    .frame(maxWidth: 240)
                Text("\(store.playbackSpeed, specifier: "%.2f")x")
            }
            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct CurrentLocationPanel: View {
    var location: CLLocation?
    var state: String

    var body: some View {
        GroupBox("Current Simulated Location") {
            VStack(alignment: .leading, spacing: 8) {
                Text("State: \(state)")
                if let location {
                    Text("Latitude: \(location.coordinate.latitude, specifier: "%.6f")")
                    Text("Longitude: \(location.coordinate.longitude, specifier: "%.6f")")
                    Text("Speed: \(location.speed, specifier: "%.2f") m/s")
                    Text("Course: \(location.course, specifier: "%.1f")")
                } else {
                    Text("No location emitted yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TargetVPNPanel: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        GroupBox("Target iPhone VPN") {
            VStack(alignment: .leading, spacing: 12) {
                Text("VPN is configured and connected on this iPhone. macOS Studio only exports node metadata.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Name")
                        TextField("QA VPN", text: $store.vpnDisplayNameText)
                    }
                    GridRow {
                        Text("Region")
                        TextField("US", text: $store.vpnRegionText)
                    }
                    GridRow {
                        Text("Server")
                        TextField("vpn.example.internal", text: $store.vpnServerHostText)
                    }
                    GridRow {
                        Text("Remote ID")
                        TextField("vpn.example.internal", text: $store.vpnRemoteIdentifierText)
                    }
                    GridRow {
                        Text("Local ID")
                        TextField("optional", text: $store.vpnLocalIdentifierText)
                    }
                    GridRow {
                        Text("Username")
                        TextField("qa", text: $store.vpnUsernameText)
                    }
                    GridRow {
                        Text("Credential Ref")
                        TextField("qa-vpn", text: $store.vpnCredentialReferenceText)
                    }
                    GridRow {
                        Text("Secret")
                        SecureField("Saved to iOS Keychain only", text: $store.vpnCredentialSecret)
                    }
                }
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Secret") { store.saveVPNSecret() }
                    Button("Configure") { Task { await store.configureVPN() } }
                    Button("Connect") { Task { await store.connectVPN() } }
                    Button("Disconnect") { store.disconnectVPN() }
                    Spacer()
                    Text("Status: \(store.vpnStatusText)")
                        .font(.system(.callout, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DiagnosticsPanel: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        GroupBox("Target Device IP / DNS Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Latency endpoint")
                        TextField("https://www.apple.com/library/test/success.html", text: $store.vpnLatencyEndpointText)
                    }
                    GridRow {
                        Text("IP endpoint")
                        TextField("https://api.ipify.org?format=json", text: $store.vpnIPEndpointText)
                    }
                    GridRow {
                        Text("DNS domains")
                        TextField("example.com, apple.com", text: $store.vpnDNSDomainsText)
                    }
                    GridRow {
                        Text("Expected country")
                        TextField("US", text: $store.vpnExpectedCountryText)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(store.isRunningDiagnostics ? "Running..." : "Run On This iPhone") {
                    store.runDiagnostics()
                }
                .disabled(store.isRunningDiagnostics)

                Text(store.diagnosticsText.isEmpty ? "No diagnostics yet." : store.diagnosticsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct TelemetryPreviewPanel: View {
    var preview: TelemetryEventPreview

    var body: some View {
        GroupBox("Telemetry Event Preview") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Read-only payload preview. It is not sent to production telemetry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(preview.payloadFields, id: \.0) { key, value in
                    HStack(alignment: .top) {
                        Text(key)
                            .foregroundStyle(.secondary)
                            .frame(width: 160, alignment: .leading)
                        Text(value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ImportScenarioPanel: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        GroupBox("Import Scenario JSON") {
            VStack(alignment: .leading) {
                TextEditor(text: $store.importText)
                    .frame(height: 120)
                    .border(.separator)
                Button("Import") { store.importScenario() }
            }
        }
    }
}

struct TelemetryEventsPanel: View {
    var events: [TelemetryEvent]

    var body: some View {
        GroupBox("Telemetry Events") {
            VStack(alignment: .leading, spacing: 8) {
                if events.isEmpty {
                    Text("No events recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events.indices, id: \.self) { index in
                        let event = events[index]
                        Text("\(event.source) \(event.latitude, specifier: "%.5f"), \(event.longitude, specifier: "%.5f") simulated=\(event.isSimulated.description) vpn=\(event.vpnNodeID ?? "-") country=\(event.ipCountryCode ?? "-") dnsLeak=\(event.dnsLeakDetected?.description ?? "-")")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
