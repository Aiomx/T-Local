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
    var errorMessage: String?

    private var playbackTask: Task<Void, Never>?
    private let eventSink = InMemoryTelemetryEventSink()
    private let diagnostics: NetworkDiagnosticsClient = URLSessionNetworkDiagnosticsClient()

    var selectedScenario: TelemetryScenario {
        scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
    }

    init() {
        selectedScenarioID = scenarios.first?.id
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
                        vpnNodeID: scenario.networkProfile?.vpnNode?.id,
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
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runDiagnostics() {
        let scenario = selectedScenario
        Task {
            do {
                var lines: [String] = []
                if let url = scenario.networkProfile?.vpnNode?.healthCheckURL ?? URL(string: "https://example.com") {
                    let latency = try await diagnostics.measureLatency(to: url)
                    lines.append("Latency: \(Int(latency.milliseconds)) ms (\(latency.statusCode ?? 0))")
                }
                if let ipURL = URL(string: "https://api.ipify.org?format=json") {
                    let ip = try await diagnostics.fetchIPGeolocation(from: ipURL)
                    lines.append("Public IP: \(ip.ipAddress)")
                    if let country = ip.countryCode {
                        lines.append("Country: \(country)")
                    }
                }
                let dns = try await diagnostics.checkDNSLeak(
                    domains: scenario.networkProfile?.dnsTestDomains ?? ["example.com"],
                    expectedCountryCode: scenario.networkProfile?.expectedCountryCode
                )
                lines.append("DNS leak detected: \(dns.leakDetected ? "yes" : "no")")
                diagnosticsText = lines.joined(separator: "\n")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Header(store: store)
                    CurrentLocationPanel(location: store.currentLocation, state: store.playbackState)
                    DiagnosticsPanel(store: store)
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

struct DiagnosticsPanel: View {
    @Bindable var store: QAConsoleStore

    var body: some View {
        GroupBox("VPN / IP Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                Button("Run Diagnostics") { store.runDiagnostics() }
                Text(store.diagnosticsText.isEmpty ? "No diagnostics yet." : store.diagnosticsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                        Text("\(event.source) \(event.latitude, specifier: "%.5f"), \(event.longitude, specifier: "%.5f") simulated=\(event.isSimulated.description)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
