import MapKit
import AppKit
import SwiftUI
import TelemetryLocationKit
import UniformTypeIdentifiers

@main
struct TelemetryScenarioStudioApp: App {
    @State private var store = ScenarioStudioStore()
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ScenarioStudioView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    appDelegate.store = store
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ScenarioStudioStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasActiveSimulation else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = store.text("active_simulation_exit_title")
        alert.informativeText = store.text("active_simulation_exit_body")
        alert.addButton(withTitle: store.text("clear_and_quit"))
        alert.addButton(withTitle: store.text("cancel"))
        alert.addButton(withTitle: store.text("quit_without_clearing"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await store.clearAllSimulatedLocationBeforeExit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateCancel
        default:
            return .terminateNow
        }
    }
}

@MainActor
@Observable
final class ScenarioStudioStore {
    var scenarios: [TelemetryScenario] = []
    var selectedScenarioID: String?
    var selectedModule: StudioModule = .scenarios
    var sidebarSelection: StudioSidebarSelection?
    var developerDevices: [DeveloperDevice] = []
    var selectedDeveloperDeviceID: String? {
        didSet {
            if oldValue != selectedDeveloperDeviceID {
                stopRoutePlayback(resetToIdle: true)
                stopGPXPlayback()
                deviceHealthCheck = nil
            }
        }
    }
    var developerDeviceStatus: String?
    var isRefreshingDeveloperDevices = false
    var locationLatitudeText = "31.2304"
    var locationLongitudeText = "121.4737"
    var routePlaybackState: RoutePlaybackState = .idle
    var routePlaybackSpeed: Double = 1
    var routePlaybackLoops = false
    var routeTimelineTime: TimeInterval = 0
    var routeTimelinePreviewCoordinate: CLLocationCoordinate2D?
    var gpxPlaybackState = GPXPlaybackStatus()
    var selectedTemplateKind: ParameterizedScenarioKind = .delivery
    var templateStartLatitudeText = "31.2304"
    var templateStartLongitudeText = "121.4737"
    var templateEndLatitudeText = "31.2330"
    var templateEndLongitudeText = "121.4802"
    var templateSpeedText = "8"
    var templateStartDwellText = "30"
    var templateEndDwellText = "45"
    var isGeneratingParameterizedTemplate = false
    var deviceHealthCheck: DeviceHealthCheck?
    var isRunningHealthCheck = false
    var deviceLocationStatus = DeviceLocationStatusSnapshot()
    var recentLocations: [SavedMapLocation] = []
    var favoriteLocations: [SavedMapLocation] = []
    var presetLocationGroups = LocationPresetGroup.defaults
    var xcodeWorkspacePath: String
    var xcodeWorkspaceName: String
    var xcodeSchemeName = ""
    var xcodeDestination = ""
    var xcodeDebugStatus: String?
    var generatedDebugGPXPath: String?
    var selectedPointID: String?
    var plannedRoute: [MapCoordinate] = []
    var routeMapMode: RouteMapMode = .straightLine
    var isPlannedRouteStale = false
    var isPlanningRoute = false
    var exportedGPX: String = ""
    var exportedJSON: String = ""
    var importText: String = ""
    var scenarioRenameText: String = ""
    var scenarioLibraryDirectoryPath: String = ""
    var scenarioSearchText: String = ""
    var selectedScenarioTag: String?
    var scenarioTagKeyText: String = ""
    var scenarioTagValueText: String = ""
    var scenarioLibraryStatus: String?
    var scenarioLibrarySaveError: String?
    var recentScenarioIDs: [String] = []
    var networkLatencyEndpointText = "https://www.apple.com/library/test/success.html"
    var networkIPEndpointText = "https://api.ipify.org?format=json"
    var networkDNSDomainsText = "example.com, apple.com"
    var networkExpectedCountryText = ""
    var networkDiagnosticsStatus: String?
    var isRunningNetworkDiagnostics = false
    var latencyResult: LatencyResult?
    var ipGeolocationResult: IPGeolocationResult?
    var dnsLeakResult: DNSLeakResult?
    var killSwitchEnabled = false
    var selectedVPNNodeID: String?
    var vpnNodes: [VPNNode] = [
        VPNNode(
            displayName: "QA US West",
            regionCode: "US",
            serverHost: "us-west.vpn.internal",
            remoteIdentifier: "us-west.vpn.internal",
            authentication: .usernamePassword(username: "qa", passwordReference: "keychain:vpn-us-west"),
            dnsServers: ["1.1.1.1"],
            healthCheckURL: URL(string: "https://www.apple.com/library/test/success.html")
        ),
        VPNNode(
            displayName: "QA Singapore",
            regionCode: "SG",
            serverHost: "sg.vpn.internal",
            remoteIdentifier: "sg.vpn.internal",
            authentication: .usernamePassword(username: "qa", passwordReference: "keychain:vpn-sg"),
            dnsServers: ["8.8.8.8"],
            healthCheckURL: URL(string: "https://www.apple.com/library/test/success.html")
        )
    ]
    var errorMessage: String?
    var language: StudioLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
        }
    }

    private static let languageDefaultsKey = "TelemetryScenarioStudio.language"
    private static let scenariosDefaultsKey = "TelemetryScenarioStudio.scenarios"
    private static let scenarioLibraryDirectoryDefaultsKey = "TelemetryScenarioStudio.scenarioLibraryDirectory"
    private static let recentScenarioIDsDefaultsKey = "TelemetryScenarioStudio.recentScenarioIDs"
    private static let recentLocationsDefaultsKey = "TelemetryScenarioStudio.recentLocations"
    private static let favoriteLocationsDefaultsKey = "TelemetryScenarioStudio.favoriteLocations"
    @ObservationIgnored private var routePlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var gpxPlaybackTask: Task<Void, Never>?
    private let developerDeviceService = DeveloperDeviceService()
    private let xcodeDebugSessionService = XcodeDebugSessionService()
    private let networkDiagnostics = URLSessionNetworkDiagnosticsClient()

    var selectedScenario: TelemetryScenario {
        get {
            scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
        }
        set {
            if selectedScenarioID != nil, selectedScenarioID != newValue.id {
                stopRoutePlayback(resetToIdle: true)
                stopGPXPlayback()
            }
            if let index = scenarios.firstIndex(where: { $0.id == newValue.id }) {
                scenarios[index] = newValue
            }
            selectedScenarioID = newValue.id
            sidebarSelection = .scenario(newValue.id)
            scenarioRenameText = newValue.name
            markScenarioRecentlyOpened(newValue.id)
            updateRouteTimeline(time: min(routeTimelineTime, newValue.duration))
            saveScenarios()
        }
    }

    var selectedVPNNode: VPNNode? {
        vpnNodes.first { $0.id == selectedVPNNodeID }
    }

    var telemetryPreview: TelemetryEventPreview {
        let scenario = selectedScenario
        let pointIndex = routeTimelinePointIndex ?? scenario.route.firstIndex { $0.id == selectedPointID }
        let point = pointIndex.flatMap { scenario.route.indices.contains($0) ? scenario.route[$0] : nil }
        let location: CLLocation?
        if let coordinate = routeTimelinePreviewCoordinate {
            location = CLLocation(
                coordinate: coordinate,
                altitude: point?.altitude ?? 0,
                horizontalAccuracy: point?.horizontalAccuracy ?? 5,
                verticalAccuracy: point?.verticalAccuracy ?? 5,
                course: point?.course ?? -1,
                speed: point?.speed ?? 0,
                timestamp: Date()
            )
        } else {
            location = nil
        }
        return TelemetryEventPreview.scenarioPreview(
            scenario: scenario,
            location: location,
            routePoint: point ?? scenario.route.first,
            routePointIndex: pointIndex,
            routeElapsedSeconds: routeTimelineTime,
            ipResult: ipGeolocationResult,
            dnsResult: dnsLeakResult
        )
    }

    var deviceTelemetryPreview: TelemetryEventPreview? {
        guard let coordinate = deviceLocationStatus.coordinate else {
            return nil
        }
        return TelemetryEventPreview(
            scenarioID: deviceLocationStatus.scenarioID ?? selectedScenario.id,
            source: "qa_sdk",
            isSimulated: true,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            scenarioName: deviceLocationStatus.scenarioName ?? selectedScenario.name,
            routePointIndex: deviceLocationStatus.pointIndex,
            routeElapsedSeconds: deviceLocationStatus.pointIndex.flatMap { index in
                selectedScenario.route.indices.contains(index) ? selectedScenario.route[index].elapsedSeconds : nil
            },
            vpnNodeID: selectedScenario.networkProfile?.vpnNode?.id,
            vpnNodeName: selectedScenario.networkProfile?.vpnNode?.displayName,
            vpnRegionCode: selectedScenario.networkProfile?.vpnNode?.regionCode ?? selectedScenario.networkProfile?.regionCode,
            publicIPAddress: ipGeolocationResult?.ipAddress,
            ipCountryCode: ipGeolocationResult?.countryCode ?? selectedScenario.networkProfile?.expectedCountryCode,
            dnsLeakDetected: dnsLeakResult?.leakDetected,
            tags: selectedScenario.expectedTelemetryTags
        )
    }

    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: Self.languageDefaultsKey)
        self.language = savedLanguage.flatMap(StudioLanguage.init(rawValue:)) ?? .english
        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultLibraryDirectory = ScenarioLibrary.defaultDirectory(in: applicationSupportDirectory)
        self.scenarioLibraryDirectoryPath = UserDefaults.standard.string(forKey: Self.scenarioLibraryDirectoryDefaultsKey) ?? defaultLibraryDirectory.path
        self.scenarios = []
        self.recentScenarioIDs = UserDefaults.standard.stringArray(forKey: Self.recentScenarioIDsDefaultsKey) ?? []
        let defaultWorkspacePath = xcodeDebugSessionService.defaultWorkspacePath()
        self.xcodeWorkspacePath = defaultWorkspacePath
        self.xcodeWorkspaceName = URL(fileURLWithPath: defaultWorkspacePath).lastPathComponent
        self.xcodeSchemeName = "TelemetryQAConsole"
        loadScenarioLibrary()
        selectedScenarioID = scenarios.first?.id
        sidebarSelection = scenarios.first.map { .scenario($0.id) }
        selectedPointID = scenarios.first?.route.first?.id
        scenarioRenameText = scenarios.first?.name ?? ""
        updateRouteTimeline(time: selectedScenario.route.first?.elapsedSeconds ?? 0)
        recentLocations = Self.loadLocations(forKey: Self.recentLocationsDefaultsKey)
        favoriteLocations = Self.loadLocations(forKey: Self.favoriteLocationsDefaultsKey)
        selectedVPNNodeID = vpnNodes.first?.id
    }

    func addPoint() {
        var scenario = selectedScenario
        let last = scenario.route.last
        let elapsed = (last?.elapsedSeconds ?? 0) + 60
        let point = RoutePoint(
            latitude: (last?.latitude ?? 31.2304) + 0.001,
            longitude: (last?.longitude ?? 121.4737) + 0.001,
            speed: last?.speed ?? 5,
            elapsedSeconds: elapsed,
            label: pointLabel(scenario.route.count + 1)
        )
        scenario.route.append(point)
        selectedScenario = scenario
        selectedPointID = point.id
        updateRouteTimeline(time: point.elapsedSeconds)
        markRouteGeometryChanged()
    }

    func addPoint(at coordinate: CLLocationCoordinate2D) {
        var scenario = selectedScenario
        let last = scenario.route.last
        let elapsed = (last?.elapsedSeconds ?? 0) + 60
        let point = RoutePoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            speed: last?.speed ?? 5,
            elapsedSeconds: elapsed,
            label: pointLabel(scenario.route.count + 1)
        )
        scenario.route.append(point)
        selectedScenario = scenario
        selectedPointID = point.id
        updateRouteTimeline(time: point.elapsedSeconds)
        markRouteGeometryChanged()
    }

    func removePoint(_ point: RoutePoint) {
        var scenario = selectedScenario
        guard scenario.route.count > 1 else {
            errorMessage = text("route_keep_one_point")
            return
        }
        scenario.route.removeAll { $0.id == point.id }
        selectedScenario = scenario
        selectedPointID = scenario.route.first?.id
        updateRouteTimeline(time: selectedScenario.route.first?.elapsedSeconds ?? 0)
        markRouteGeometryChanged()
    }

    func selectPoint(_ point: RoutePoint) {
        selectedPointID = point.id
        updateRouteTimeline(time: point.elapsedSeconds)
    }

    func updatePoint(_ pointID: String, coordinate: CLLocationCoordinate2D) {
        var scenario = selectedScenario
        guard let index = scenario.route.firstIndex(where: { $0.id == pointID }) else {
            return
        }
        scenario.route[index].latitude = coordinate.latitude
        scenario.route[index].longitude = coordinate.longitude
        selectedScenario = scenario
        selectedPointID = pointID
        updateRouteTimeline(time: scenario.route[index].elapsedSeconds)
        markRouteGeometryChanged()
    }

    func swapRouteEndpoints() {
        guard selectedScenario.route.count > 1 else {
            errorMessage = text("route_swap_needs_two_points")
            return
        }
        selectedScenario = selectedScenario.reversedRoutePreservingTiming()
        selectedPointID = selectedScenario.route.first?.id
        updateRouteTimeline(time: 0)
        markRouteGeometryChanged()
        errorMessage = nil
    }

    private func markRouteGeometryChanged() {
        if routeMapMode == .roadPlanning {
            isPlannedRouteStale = true
        } else {
            plannedRoute = []
            isPlannedRouteStale = false
        }
    }

    func planRoute() async {
        let route = selectedScenario.route
        guard route.count >= 2 else {
            errorMessage = text("error_route_needs_two_points")
            return
        }

        isPlanningRoute = true
        errorMessage = nil

        do {
            var coordinates: [MapCoordinate] = []
            for index in 0..<(route.count - 1) {
                let segment = try await directions(from: route[index], to: route[index + 1])
                let segmentCoordinates = segment.polyline.coordinates.map(MapCoordinate.init)
                if coordinates.isEmpty {
                    coordinates.append(contentsOf: segmentCoordinates)
                } else {
                    coordinates.append(contentsOf: segmentCoordinates.dropFirst())
                }
            }
            plannedRoute = coordinates
            routeMapMode = .roadPlanning
            isPlannedRouteStale = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isPlanningRoute = false
    }

    func applyPlannedRoute() {
        guard !plannedRoute.isEmpty else {
            errorMessage = text("error_plan_before_apply")
            return
        }

        let existing = selectedScenario
        let interval: TimeInterval = 30
        let points = plannedRoute.enumerated().map { index, coordinate in
            RoutePoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                speed: 8,
                elapsedSeconds: TimeInterval(index) * interval,
                label: index == 0 ? text("start") : (index == plannedRoute.count - 1 ? text("end") : nil)
            )
        }

        selectedScenario = TelemetryScenario(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            route: points,
            networkProfile: existing.networkProfile,
            expectedTelemetryTags: existing.expectedTelemetryTags
        )
        selectedPointID = points.first?.id
        updateRouteTimeline(time: points.first?.elapsedSeconds ?? 0)
        routeMapMode = .roadPlanning
        isPlannedRouteStale = false
        errorMessage = nil
    }

    func setRouteMapMode(_ mode: RouteMapMode) {
        routeMapMode = mode
        if mode == .straightLine {
            plannedRoute = []
            isPlannedRouteStale = false
        } else if plannedRoute.isEmpty, selectedScenario.route.count >= 2 {
            isPlannedRouteStale = true
        }
    }

    func useCurrentLocationAsTemplateStart() {
        guard let coordinate = manualDeviceLocationCoordinate else {
            errorMessage = text("developer_devices_invalid_coordinate")
            return
        }
        templateStartLatitudeText = String(format: "%.6f", coordinate.latitude)
        templateStartLongitudeText = String(format: "%.6f", coordinate.longitude)
    }

    func useCurrentLocationAsTemplateEnd() {
        guard let coordinate = manualDeviceLocationCoordinate else {
            errorMessage = text("developer_devices_invalid_coordinate")
            return
        }
        templateEndLatitudeText = String(format: "%.6f", coordinate.latitude)
        templateEndLongitudeText = String(format: "%.6f", coordinate.longitude)
    }

    func generateParameterizedTemplate() async {
        guard let start = templateStartCoordinate,
              let end = templateEndCoordinate,
              let speed = Double(templateSpeedText), speed > 0,
              let startDwell = Double(templateStartDwellText), startDwell >= 0,
              let endDwell = Double(templateEndDwellText), endDwell >= 0 else {
            errorMessage = text("template_invalid_parameters")
            return
        }

        isGeneratingParameterizedTemplate = true
        errorMessage = nil

        do {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
            request.transportType = selectedTemplateKind.transportType
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw ScenarioStudioError.noRouteFound
            }

            var coordinates = route.polyline.coordinates
            if coordinates.isEmpty {
                coordinates = [start, end]
            }
            if coordinates.first.map({ distance(from: $0, to: start) > 5 }) ?? true {
                coordinates.insert(start, at: 0)
            }
            if coordinates.last.map({ distance(from: $0, to: end) > 5 }) ?? true {
                coordinates.append(end)
            }

            let points = routePoints(
                from: coordinates,
                speed: speed,
                startDwell: startDwell,
                endDwell: endDwell,
                kind: selectedTemplateKind
            )
            let existing = selectedScenario
            selectedScenario = TelemetryScenario(
                id: existing.id,
                name: selectedTemplateKind.scenarioName(in: self),
                description: selectedTemplateKind.scenarioDescription(in: self),
                route: points,
                networkProfile: existing.networkProfile,
                expectedTelemetryTags: [
                    "template": selectedTemplateKind.rawValue,
                    "is_simulated": "true"
                ]
            )
            selectedPointID = points.first?.id
            updateRouteTimeline(time: points.first?.elapsedSeconds ?? 0)
            plannedRoute = []
            exportedGPX = ""
            exportedJSON = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isGeneratingParameterizedTemplate = false
    }

    private var templateStartCoordinate: CLLocationCoordinate2D? {
        coordinate(latitudeText: templateStartLatitudeText, longitudeText: templateStartLongitudeText)
    }

    private var templateEndCoordinate: CLLocationCoordinate2D? {
        coordinate(latitudeText: templateEndLatitudeText, longitudeText: templateEndLongitudeText)
    }

    private func coordinate(latitudeText: String, longitudeText: String) -> CLLocationCoordinate2D? {
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText) else {
            return nil
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func routePoints(
        from coordinates: [CLLocationCoordinate2D],
        speed: Double,
        startDwell: TimeInterval,
        endDwell: TimeInterval,
        kind: ParameterizedScenarioKind
    ) -> [RoutePoint] {
        guard !coordinates.isEmpty else {
            return []
        }

        var elapsed: TimeInterval = 0
        var points: [RoutePoint] = []
        for index in coordinates.indices {
            if index > 0 {
                elapsed += distance(from: coordinates[index - 1], to: coordinates[index]) / speed
            }
            points.append(
                RoutePoint(
                    latitude: coordinates[index].latitude,
                    longitude: coordinates[index].longitude,
                    speed: index == 0 || index == coordinates.count - 1 ? 0 : speed,
                    elapsedSeconds: elapsed,
                    dwellSeconds: index == 0 ? startDwell : (index == coordinates.count - 1 ? endDwell : 0),
                    label: kind.pointLabel(index: index, total: coordinates.count, in: self)
                )
            )
            if index == 0 {
                elapsed += startDwell
            }
        }
        return points
    }

    private func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private func directions(from start: RoutePoint, to end: RoutePoint) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw ScenarioStudioError.noRouteFound
        }
        return route
    }

    func exportGPX() {
        do {
            exportedGPX = try GPXExporter.export(selectedScenario)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportJSON() {
        do {
            let data = try ScenarioCodec.encode(selectedScenario)
            exportedJSON = String(decoding: data, as: UTF8.self)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importJSON() {
        do {
            let scenario = try ScenarioCodec.decode(Data(importText.utf8))
            scenarios.append(scenario)
            selectedScenarioID = scenario.id
            sidebarSelection = .scenario(scenario.id)
            selectedPointID = scenario.route.first?.id
            scenarioRenameText = scenario.name
            markScenarioRecentlyOpened(scenario.id)
            saveScenarios()
            plannedRoute = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSidebar(_ selection: StudioSidebarSelection?) {
        if case let .scenario(id) = selection,
           id != selectedScenarioID,
           !confirmSimulationChangeIfNeeded() {
            return
        }
        sidebarSelection = selection
        switch selection {
        case let .scenario(id):
            selectedModule = .scenarios
            selectedScenarioID = id
            selectedPointID = selectedScenario.route.first?.id
            scenarioRenameText = selectedScenario.name
            markScenarioRecentlyOpened(id)
            updateRouteTimeline(time: selectedScenario.route.first?.elapsedSeconds ?? 0)
            plannedRoute = []
        case .developerDevices:
            selectedModule = .developerDevices
        case .network:
            selectedModule = .network
        case .settings:
            selectedModule = .settings
        case nil:
            break
        }
    }

    func selectDeveloperDevice(_ device: DeveloperDevice) {
        guard device.id != selectedDeveloperDeviceID else {
            return
        }
        guard confirmSimulationChangeIfNeeded() else {
            return
        }
        selectedDeveloperDeviceID = device.id
    }

    func selectModule(_ module: StudioModule) {
        selectedModule = module
        switch module {
        case .scenarios:
            let id = selectedScenarioID ?? scenarios.first?.id
            selectedScenarioID = id
            sidebarSelection = id.map { .scenario($0) }
        case .developerDevices:
            sidebarSelection = .developerDevices
        case .network:
            sidebarSelection = .network
        case .settings:
            sidebarSelection = .settings
        }
    }

    func refreshDeveloperDevices() async {
        isRefreshingDeveloperDevices = true
        developerDeviceStatus = nil

        do {
            developerDevices = try await developerDeviceService.listDevices()
            if selectedDeveloperDeviceID == nil || !developerDevices.contains(where: { $0.id == selectedDeveloperDeviceID }) {
                selectedDeveloperDeviceID = developerDevices.first?.id
            }
            updateXcodeDestinationFromSelectedDevice()
            developerDeviceStatus = String(format: text("developer_devices_found"), developerDevices.count)
        } catch {
            developerDeviceStatus = error.localizedDescription
        }

        isRefreshingDeveloperDevices = false
    }

    @discardableResult
    private func confirmSimulationChangeIfNeeded() -> Bool {
        guard hasActiveSimulation else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = text("active_simulation_switch_title")
        alert.informativeText = text("active_simulation_switch_body")
        alert.addButton(withTitle: text("clear_and_continue"))
        alert.addButton(withTitle: text("cancel"))
        alert.addButton(withTitle: text("continue_without_clearing"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await clearAllSimulatedLocationBeforeExit() }
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return true
        }
    }

    func setSelectedDeviceLocation() async {
        guard let selectedDevice else {
            developerDeviceStatus = text("developer_devices_select_first")
            return
        }
        guard let latitude = Double(locationLatitudeText), let longitude = Double(locationLongitudeText) else {
            developerDeviceStatus = text("developer_devices_invalid_coordinate")
            return
        }

        do {
            try await developerDeviceService.setLocation(device: selectedDevice, latitude: latitude, longitude: longitude)
            recordAppliedLocation(
                device: selectedDevice,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                source: .manual,
                scenario: nil,
                pointIndex: nil,
                totalPoints: nil
            )
            developerDeviceStatus = text("developer_devices_location_set")
        } catch {
            routePlaybackState = .failed
            developerDeviceStatus = error.localizedDescription
        }
    }

    func clearSelectedDeviceLocation() async {
        guard let selectedDevice else {
            developerDeviceStatus = text("developer_devices_select_first")
            return
        }

        do {
            try await developerDeviceService.clearLocation(device: selectedDevice)
            stopRoutePlayback(resetToIdle: true)
            deviceLocationStatus = DeviceLocationStatusSnapshot(
                playbackState: .idle,
                source: .cleared,
                deviceName: selectedDevice.name,
                deviceID: selectedDevice.id,
                scenarioName: nil,
                scenarioID: nil,
                coordinate: nil,
                appliedAt: Date(),
                pointIndex: nil,
                totalPoints: nil,
                playbackSpeed: routePlaybackSpeed,
                loops: routePlaybackLoops
            )
            developerDeviceStatus = text("developer_devices_location_cleared")
        } catch {
            developerDeviceStatus = error.localizedDescription
        }
    }

    func updateManualDeviceLocation(_ coordinate: CLLocationCoordinate2D) {
        locationLatitudeText = String(format: "%.6f", coordinate.latitude)
        locationLongitudeText = String(format: "%.6f", coordinate.longitude)
    }

    func useScenarioStartForDeviceLocation() {
        guard let point = selectedScenario.route.first else {
            developerDeviceStatus = text("error_route_needs_two_points")
            return
        }
        updateManualDeviceLocation(point.coordinate)
        if let selectedDevice {
            recordAppliedLocation(
                device: selectedDevice,
                coordinate: point.coordinate,
                source: .scenarioStart,
                scenario: selectedScenario,
                pointIndex: 0,
                totalPoints: selectedScenario.route.count
            )
        }
    }

    var manualDeviceLocationCoordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(locationLatitudeText),
              let longitude = Double(locationLongitudeText),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func useSelectedDeviceForXcodeDestination() {
        updateXcodeDestinationFromSelectedDevice()
        xcodeDebugStatus = text("xcode_destination_set")
    }

    private func updateXcodeDestinationFromSelectedDevice() {
        guard let selectedDevice else {
            return
        }

        let identifier = selectedDevice.udid ?? selectedDevice.id
        switch selectedDevice.kind {
        case .physical:
            xcodeDestination = "platform=iOS,id=\(identifier)"
        case .simulator:
            xcodeDestination = "platform=iOS Simulator,id=\(identifier)"
        }
    }

    private func refreshXcodeDebugDefaults() {
        if xcodeWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            xcodeWorkspacePath = xcodeDebugSessionService.defaultWorkspacePath()
        }
        if xcodeWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            xcodeWorkspaceName = URL(fileURLWithPath: xcodeWorkspacePath).lastPathComponent
        }
        if xcodeSchemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            xcodeSchemeName = xcodeDebugSessionService.defaultRunnableScheme(workspaceOrProjectPath: xcodeWorkspacePath) ?? "TelemetryQAConsole"
        }
        updateXcodeDestinationFromSelectedDevice()
    }

    func generateXcodeDebugGPX() {
        do {
            refreshXcodeDebugDefaults()
            let url = try xcodeDebugSessionService.writeDebugGPX(for: selectedScenario)
            let schemeURL = try xcodeDebugSessionService.configureSchemeLocation(
                workspaceOrProjectPath: xcodeWorkspacePath,
                schemeName: xcodeSchemeName,
                gpxURL: url
            )
            generatedDebugGPXPath = url.path
            xcodeDebugStatus = String(format: text("xcode_gpx_generated"), url.path, schemeURL.path)
        } catch {
            xcodeDebugStatus = error.localizedDescription
        }
    }

    func launchXcodeDebugSession() async {
        guard let selectedDevice else {
            xcodeDebugStatus = text("developer_devices_select_first")
            return
        }
        guard let point = selectedScenario.route.first else {
            xcodeDebugStatus = text("error_route_needs_two_points")
            return
        }

        do {
            try await developerDeviceService.setLocation(
                device: selectedDevice,
                latitude: point.latitude,
                longitude: point.longitude
            )
            recordAppliedLocation(
                device: selectedDevice,
                coordinate: point.coordinate,
                source: .scenarioStart,
                scenario: selectedScenario,
                pointIndex: 0,
                totalPoints: selectedScenario.route.count
            )
            xcodeDebugStatus = String(
                format: text("xcode_debug_started"),
                selectedDevice.name,
                point.latitude,
                point.longitude
            )
        } catch {
            xcodeDebugStatus = error.localizedDescription
        }
    }

    func refreshSelectedDeviceHealth() async {
        guard let selectedDevice else {
            developerDeviceStatus = text("developer_devices_select_first")
            return
        }
        isRunningHealthCheck = true
        deviceHealthCheck = await developerDeviceService.runHealthCheck(device: selectedDevice)
        isRunningHealthCheck = false
    }

    func copyHealthReportMarkdown() {
        guard let deviceHealthCheck else {
            return
        }
        copyToPasteboard(deviceHealthCheck.markdownReport)
        developerDeviceStatus = text("health_report_copied")
    }

    func copyHealthReportJSON() {
        guard let deviceHealthCheck else {
            return
        }
        copyToPasteboard(deviceHealthCheck.jsonReport)
        developerDeviceStatus = text("health_report_copied")
    }

    func copyTelemetryPreviewJSON(deviceState: Bool = false) {
        let preview = deviceState ? (deviceTelemetryPreview ?? telemetryPreview) : telemetryPreview
        copyToPasteboard(preview.prettyPrintedJSONString)
        networkDiagnosticsStatus = text("telemetry_json_copied")
    }

    func copyTelemetryPreviewFields(deviceState: Bool = false) {
        let preview = deviceState ? (deviceTelemetryPreview ?? telemetryPreview) : telemetryPreview
        let fieldText = preview.payloadFields.map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
        copyToPasteboard(fieldText)
        networkDiagnosticsStatus = text("telemetry_fields_copied")
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func startGPXPlaybackToDevice() {
        guard let selectedDevice else {
            xcodeDebugStatus = text("developer_devices_select_first")
            return
        }
        guard selectedDevice.locationCapability.isAvailable else {
            xcodeDebugStatus = text("playback_device_unavailable")
            gpxPlaybackState = GPXPlaybackStatus(state: .failed, message: text("playback_device_unavailable"))
            return
        }

        do {
            let gpx = try GPXExporter.export(selectedScenario)
            let points = try GPXTrackPointParser.parse(gpx)
            guard !points.isEmpty else {
                throw ScenarioStudioError.emptyGPXTrack
            }
            stopGPXPlayback()
            gpxPlaybackState = GPXPlaybackStatus(
                state: .running,
                deviceName: selectedDevice.name,
                scenarioName: selectedScenario.name,
                currentIndex: 0,
                totalPoints: points.count,
                lastCoordinate: nil,
                message: text("gpx_playback_running")
            )
            gpxPlaybackTask = Task { [weak self] in
                await self?.runGPXPlayback(device: selectedDevice, points: points)
            }
        } catch {
            gpxPlaybackState = GPXPlaybackStatus(state: .failed, message: error.localizedDescription)
            xcodeDebugStatus = error.localizedDescription
        }
    }

    func stopGPXPlayback() {
        gpxPlaybackTask?.cancel()
        gpxPlaybackTask = nil
        if gpxPlaybackState.state == .running {
            gpxPlaybackState.state = .stopped
            gpxPlaybackState.message = text("gpx_playback_stopped")
        }
    }

    private func runGPXPlayback(device: DeveloperDevice, points: [GPXTrackPoint]) async {
        for index in points.indices {
            if Task.isCancelled {
                return
            }

            if index > 0 {
                let delay = max(0, points[index].timestamp.timeIntervalSince(points[index - 1].timestamp))
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            }

            if Task.isCancelled {
                return
            }

            let point = points[index]
            do {
                try await developerDeviceService.setLocation(
                    device: device,
                    latitude: point.coordinate.latitude,
                    longitude: point.coordinate.longitude
                )
                gpxPlaybackState = GPXPlaybackStatus(
                    state: .running,
                    deviceName: device.name,
                    scenarioName: selectedScenario.name,
                    currentIndex: index + 1,
                    totalPoints: points.count,
                    lastCoordinate: point.coordinate,
                    message: String(format: text("gpx_playback_applied_point"), index + 1, points.count)
                )
                recordAppliedLocation(
                    device: device,
                    coordinate: point.coordinate,
                    source: .gpxPlayback,
                    scenario: selectedScenario,
                    pointIndex: index,
                    totalPoints: points.count
                )
            } catch {
                gpxPlaybackState.state = .failed
                gpxPlaybackState.message = error.localizedDescription
                xcodeDebugStatus = error.localizedDescription
                gpxPlaybackTask = nil
                return
            }
        }

        gpxPlaybackState.state = .completed
        gpxPlaybackState.message = text("gpx_playback_completed")
        gpxPlaybackTask = nil
    }

    var xcodeDebugSummary: String {
        let device = selectedDevice?.name ?? text("automatic")
        return String(format: text("xcode_auto_summary"), device, selectedScenario.name)
    }

    var routeTimelineDuration: TimeInterval {
        selectedScenario.duration
    }

    var routeTimelinePointIndex: Int? {
        routePointIndex(at: routeTimelineTime, in: selectedScenario)
    }

    var routeTimelineSegments: [RouteTimelineSegment] {
        let route = selectedScenario.route
        guard !route.isEmpty else {
            return []
        }
        return route.indices.map { index in
            let point = route[index]
            let nextElapsed = index + 1 < route.count ? route[index + 1].elapsedSeconds : point.elapsedSeconds
            return RouteTimelineSegment(
                id: point.id,
                index: index,
                label: point.label ?? pointLabel(index + 1),
                elapsedSeconds: point.elapsedSeconds,
                dwellSeconds: point.dwellSeconds,
                segmentSeconds: max(0, nextElapsed - point.elapsedSeconds - point.dwellSeconds),
                coordinate: point.coordinate
            )
        }
    }

    func updateRouteTimeline(time: TimeInterval) {
        guard !scenarios.isEmpty else {
            routeTimelineTime = 0
            routeTimelinePreviewCoordinate = nil
            return
        }

        let scenario = selectedScenario
        let clamped = min(max(0, time), scenario.duration)
        routeTimelineTime = clamped

        if let interpolator = try? RouteInterpolator(scenario: scenario) {
            routeTimelinePreviewCoordinate = interpolator.location(at: clamped).coordinate
        } else {
            routeTimelinePreviewCoordinate = scenario.route.first?.coordinate
        }

        if let index = routePointIndex(at: clamped, in: scenario), scenario.route.indices.contains(index) {
            selectedPointID = scenario.route[index].id
        }
    }

    func jumpRoutePlayback(to time: TimeInterval) {
        updateRouteTimeline(time: time)
        guard routePlaybackState == .running || routePlaybackState == .paused else {
            return
        }
        guard let selectedDevice, selectedDevice.locationCapability.isAvailable else {
            return
        }

        let wasPaused = routePlaybackState == .paused
        let scenario = selectedScenario
        let startIndex = routePointIndex(at: routeTimelineTime, in: scenario) ?? 0
        stopRoutePlayback(resetToIdle: false)
        routePlaybackState = wasPaused ? .paused : .running
        deviceLocationStatus.playbackState = routePlaybackState
        routePlaybackTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.runRoutePlayback(
                device: selectedDevice,
                scenario: scenario,
                speed: max(routePlaybackSpeed, 0.1),
                loops: routePlaybackLoops,
                startIndex: startIndex
            )
        }
    }

    private func routePointIndex(at time: TimeInterval, in scenario: TelemetryScenario) -> Int? {
        guard !scenario.route.isEmpty else {
            return nil
        }
        var result = 0
        for index in scenario.route.indices where scenario.route[index].elapsedSeconds <= time {
            result = index
        }
        return result
    }

    func startRoutePlayback() {
        guard let selectedDevice else {
            developerDeviceStatus = text("developer_devices_select_first")
            return
        }
        guard selectedDevice.locationCapability.isAvailable else {
            developerDeviceStatus = text("playback_device_unavailable")
            routePlaybackState = .failed
            return
        }
        let scenario = selectedScenario
        guard !scenario.route.isEmpty else {
            developerDeviceStatus = text("playback_route_empty")
            routePlaybackState = .failed
            return
        }

        stopRoutePlayback(resetToIdle: false)
        routePlaybackState = .running
        deviceLocationStatus = DeviceLocationStatusSnapshot(
            playbackState: .running,
            source: .scenarioPlayback,
            deviceName: selectedDevice.name,
            deviceID: selectedDevice.id,
            scenarioName: scenario.name,
            scenarioID: scenario.id,
            coordinate: nil,
            appliedAt: nil,
            pointIndex: 0,
            totalPoints: scenario.route.count,
            playbackSpeed: routePlaybackSpeed,
            loops: routePlaybackLoops
        )

        let speed = max(routePlaybackSpeed, 0.1)
        let shouldLoop = routePlaybackLoops
        let startIndex = routePointIndex(at: routeTimelineTime, in: scenario) ?? 0
        routePlaybackTask = Task { [weak self] in
            await self?.runRoutePlayback(device: selectedDevice, scenario: scenario, speed: speed, loops: shouldLoop, startIndex: startIndex)
        }
    }

    func pauseRoutePlayback() {
        guard routePlaybackState == .running else {
            return
        }
        routePlaybackState = .paused
        deviceLocationStatus.playbackState = .paused
        developerDeviceStatus = text("playback_paused")
    }

    func resumeRoutePlayback() {
        guard routePlaybackState == .paused else {
            return
        }
        routePlaybackState = .running
        deviceLocationStatus.playbackState = .running
        developerDeviceStatus = text("playback_resumed")
    }

    func stopRoutePlayback(resetToIdle: Bool = true) {
        routePlaybackTask?.cancel()
        routePlaybackTask = nil
        if resetToIdle {
            routePlaybackState = .idle
            deviceLocationStatus.playbackState = .idle
        }
    }

    private func runRoutePlayback(
        device: DeveloperDevice,
        scenario: TelemetryScenario,
        speed: Double,
        loops: Bool,
        startIndex: Int = 0
    ) async {
        var firstCycle = true
        repeat {
            let lowerBound = firstCycle ? min(max(startIndex, 0), max(scenario.route.count - 1, 0)) : 0
            let skipsInitialDelay = firstCycle
            firstCycle = false

            for index in scenario.route.indices.dropFirst(lowerBound) {
                if Task.isCancelled {
                    return
                }

                while routePlaybackState == .paused, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if Task.isCancelled {
                    return
                }

                if index > 0, !(skipsInitialDelay && index == lowerBound) {
                    let previous = scenario.route[index - 1]
                    let current = scenario.route[index]
                    let delay = max(0, current.elapsedSeconds - previous.elapsedSeconds) / speed
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                }

                while routePlaybackState == .paused, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if Task.isCancelled {
                    return
                }

                let point = scenario.route[index]
                do {
                    try await developerDeviceService.setLocation(
                        device: device,
                        latitude: point.latitude,
                        longitude: point.longitude
                    )
                    routePlaybackState = .running
                    recordAppliedLocation(
                        device: device,
                        coordinate: point.coordinate,
                        source: .scenarioPlayback,
                        scenario: scenario,
                        pointIndex: index,
                        totalPoints: scenario.route.count
                    )
                    updateRouteTimeline(time: point.elapsedSeconds)
                    developerDeviceStatus = String(
                        format: text("playback_applied_point"),
                        index + 1,
                        scenario.route.count,
                        device.name
                    )
                } catch {
                    routePlaybackState = .failed
                    deviceLocationStatus.playbackState = .failed
                    developerDeviceStatus = error.localizedDescription
                    routePlaybackTask = nil
                    return
                }
            }
        } while loops && !Task.isCancelled

        routePlaybackState = .completed
        deviceLocationStatus.playbackState = .completed
        routePlaybackTask = nil
        developerDeviceStatus = text("playback_completed")
    }

    private func recordAppliedLocation(
        device: DeveloperDevice,
        coordinate: CLLocationCoordinate2D,
        source: DeviceLocationSource,
        scenario: TelemetryScenario?,
        pointIndex: Int?,
        totalPoints: Int?
    ) {
        deviceLocationStatus = DeviceLocationStatusSnapshot(
            playbackState: routePlaybackState,
            source: source,
            deviceName: device.name,
            deviceID: device.id,
            scenarioName: scenario?.name,
            scenarioID: scenario?.id,
            coordinate: coordinate,
            appliedAt: Date(),
            pointIndex: pointIndex,
            totalPoints: totalPoints,
            playbackSpeed: routePlaybackSpeed,
            loops: routePlaybackLoops
        )
    }

    var hasActiveSimulation: Bool {
        routePlaybackState == .running ||
            routePlaybackState == .paused ||
            gpxPlaybackState.state == .running ||
            (deviceLocationStatus.source != .none && deviceLocationStatus.source != .cleared)
    }

    var activeSimulationSummary: String {
        let device = deviceLocationStatus.deviceName ?? selectedDevice?.name ?? text("automatic")
        let source = deviceLocationStatus.source.title(in: self)
        let coordinate: String
        if let value = deviceLocationStatus.coordinate {
            coordinate = String(format: "%.6f, %.6f", value.latitude, value.longitude)
        } else {
            coordinate = "-"
        }
        return String(format: text("active_simulation_summary"), device, source, coordinate)
    }

    func clearAllSimulatedLocationBeforeExit() async {
        stopRoutePlayback(resetToIdle: true)
        stopGPXPlayback()
        await clearSelectedDeviceLocation()
    }

    func clearGlobalSimulationStatus() async {
        if let statusDeviceID = deviceLocationStatus.deviceID,
           let selectedDeveloperDeviceID,
           statusDeviceID != selectedDeveloperDeviceID {
            developerDeviceStatus = text("global_clear_select_device_first")
            return
        }
        await clearAllSimulatedLocationBeforeExit()
    }

    func duplicateSelectedScenario() {
        let original = selectedScenario
        let scenario = TelemetryScenario(
            name: String(format: text("scenario_copy_name"), original.name),
            description: original.description,
            route: original.route.map { point in
                RoutePoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    horizontalAccuracy: point.horizontalAccuracy,
                    verticalAccuracy: point.verticalAccuracy,
                    speed: point.speed,
                    course: point.course,
                    elapsedSeconds: point.elapsedSeconds,
                    dwellSeconds: point.dwellSeconds,
                    label: point.label
                )
            },
            networkProfile: original.networkProfile,
            expectedTelemetryTags: original.expectedTelemetryTags
        )
        scenarios.append(scenario)
        selectedScenarioID = scenario.id
        sidebarSelection = .scenario(scenario.id)
        scenarioRenameText = scenario.name
        selectedPointID = scenario.route.first?.id
        markScenarioRecentlyOpened(scenario.id)
        saveScenarios()
    }

    func createScenario() {
        let point = RoutePoint(
            latitude: 31.2304,
            longitude: 121.4737,
            speed: 0,
            elapsedSeconds: 0,
            label: text("start")
        )
        let scenario = TelemetryScenario(
            name: text("new_scenario"),
            description: text("new_scenario_description"),
            route: [point],
            expectedTelemetryTags: ["is_simulated": "true"]
        )
        scenarios.append(scenario)
        selectedScenarioID = scenario.id
        sidebarSelection = .scenario(scenario.id)
        scenarioRenameText = scenario.name
        selectedPointID = point.id
        markScenarioRecentlyOpened(scenario.id)
        saveScenarios()
        errorMessage = nil
    }

    func renameSelectedScenario() {
        let name = scenarioRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = text("scenario_name_required")
            return
        }
        var scenario = selectedScenario
        scenario.name = name
        selectedScenario = scenario
        errorMessage = nil
    }

    func deleteSelectedScenario() {
        guard scenarios.count > 1, let selectedScenarioID else {
            errorMessage = text("scenario_delete_last_error")
            return
        }
        let deleted = selectedScenario
        scenarios.removeAll { $0.id == selectedScenarioID }
        recentScenarioIDs.removeAll { $0 == selectedScenarioID }
        let next = scenarios.first
        self.selectedScenarioID = next?.id
        sidebarSelection = next.map { .scenario($0.id) }
        selectedPointID = next?.route.first?.id
        scenarioRenameText = next?.name ?? ""
        try? ScenarioLibrary.delete(deleted, from: scenarioLibraryDirectory)
        saveRecentScenarioIDs()
        saveScenarios()
        errorMessage = nil
    }

    func resetScenarioLibraryToTemplates() {
        let existingIDs = Set(scenarios.map(\.id))
        let existingNames = Set(scenarios.map(\.name))
        for template in ScenarioTemplates.all where !existingIDs.contains(template.id) && !existingNames.contains(template.name) {
            scenarios.append(template)
        }
        if selectedScenarioID == nil {
            selectedScenarioID = scenarios.first?.id
            sidebarSelection = scenarios.first.map { .scenario($0.id) }
            selectedPointID = scenarios.first?.route.first?.id
            scenarioRenameText = scenarios.first?.name ?? ""
        }
        saveRecentScenarioIDs()
        saveScenarios()
    }

    var scenarioLibraryDirectory: URL {
        URL(fileURLWithPath: scenarioLibraryDirectoryPath, isDirectory: true)
    }

    var filteredScenarios: [TelemetryScenario] {
        scenarios.filter { scenario in
            scenario.matchesSearchText(scenarioSearchText) && scenario.hasTag(selectedScenarioTag)
        }
    }

    var availableScenarioTags: [String] {
        Array(Set(scenarios.flatMap { $0.expectedTelemetryTags.keys })).sorted()
    }

    var recentScenarios: [TelemetryScenario] {
        recentScenarioIDs.compactMap { id in
            scenarios.first { $0.id == id }
        }
    }

    func addSelectedScenarioTag() {
        let key = scenarioTagKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return
        }
        let value = scenarioTagValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        var scenario = selectedScenario
        scenario.expectedTelemetryTags[key] = value.isEmpty ? "true" : value
        selectedScenario = scenario
        scenarioTagKeyText = ""
        scenarioTagValueText = ""
    }

    func removeSelectedScenarioTag(_ key: String) {
        var scenario = selectedScenario
        scenario.expectedTelemetryTags.removeValue(forKey: key)
        selectedScenario = scenario
        if selectedScenarioTag == key {
            selectedScenarioTag = nil
        }
    }

    func exportSelectedScenarioFile() {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(ScenarioLibrary.safeFileStem(for: selectedScenario)).\(ScenarioCodec.fileExtension)"
            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }
            try ScenarioCodec.encode(selectedScenario).write(to: url, options: [.atomic])
            scenarioLibraryStatus = String(format: text("scenario_exported_to"), url.path)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importScenarioFile() {
        do {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = true
            guard panel.runModal() == .OK else {
                return
            }
            var existingIDs = Set(scenarios.map(\.id))
            var existingNames = Set(scenarios.map(\.name))
            var imported: [TelemetryScenario] = []
            for url in panel.urls {
                let decoded = try ScenarioCodec.decode(try Data(contentsOf: url))
                let copy = ScenarioLibrary.importedCopy(from: decoded, existingIDs: existingIDs, existingNames: existingNames)
                imported.append(copy)
                existingIDs.insert(copy.id)
                existingNames.insert(copy.name)
            }
            scenarios.append(contentsOf: imported)
            if let first = imported.first {
                selectedScenarioID = first.id
                sidebarSelection = .scenario(first.id)
                selectedPointID = first.route.first?.id
                scenarioRenameText = first.name
                markScenarioRecentlyOpened(first.id)
            }
            saveScenarios()
            scenarioLibraryStatus = String(format: text("scenario_imported_count"), imported.count)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markScenarioRecentlyOpened(_ id: String) {
        recentScenarioIDs.removeAll { $0 == id }
        recentScenarioIDs.insert(id, at: 0)
        recentScenarioIDs = Array(recentScenarioIDs.prefix(8))
        saveRecentScenarioIDs()
    }

    private func saveScenarios() {
        UserDefaults.standard.set(scenarioLibraryDirectoryPath, forKey: Self.scenarioLibraryDirectoryDefaultsKey)
        do {
            try FileManager.default.createDirectory(at: scenarioLibraryDirectory, withIntermediateDirectories: true)
            for scenario in scenarios {
                _ = try ScenarioLibrary.write(scenario, to: scenarioLibraryDirectory)
            }
            scenarioLibrarySaveError = nil
            scenarioLibraryStatus = String(format: text("scenario_autosaved"), scenarios.count)
        } catch {
            scenarioLibrarySaveError = error.localizedDescription
        }
    }

    private func loadScenarioLibrary() {
        do {
            try FileManager.default.createDirectory(at: scenarioLibraryDirectory, withIntermediateDirectories: true)
            let files = try ScenarioLibrary.loadScenarios(from: scenarioLibraryDirectory)
            if !files.isEmpty {
                scenarios = files.map(\.scenario)
                scenarioLibraryStatus = String(format: text("scenario_loaded_count"), scenarios.count)
                return
            }

            let migrated = Self.loadLegacyScenarios()
            scenarios = migrated.isEmpty ? ScenarioTemplates.all : migrated
            saveScenarios()
            scenarioLibraryStatus = String(format: text("scenario_loaded_count"), scenarios.count)
        } catch {
            scenarioLibrarySaveError = error.localizedDescription
            scenarios = Self.loadLegacyScenarios()
            if scenarios.isEmpty {
                scenarios = ScenarioTemplates.all
            }
        }
    }

    private static func loadLegacyScenarios() -> [TelemetryScenario] {
        let decoder = JSONDecoder()
        guard let data = UserDefaults.standard.data(forKey: Self.scenariosDefaultsKey),
              let scenarios = try? decoder.decode([TelemetryScenario].self, from: data),
              !scenarios.isEmpty else {
            return []
        }
        return scenarios
    }

    private func saveRecentScenarioIDs() {
        UserDefaults.standard.set(recentScenarioIDs, forKey: Self.recentScenarioIDsDefaultsKey)
    }

    func runNetworkDiagnostics() async {
        guard let latencyURL = URL(string: networkLatencyEndpointText),
              let ipURL = URL(string: networkIPEndpointText) else {
            networkDiagnosticsStatus = text("network_invalid_endpoints")
            return
        }

        isRunningNetworkDiagnostics = true
        networkDiagnosticsStatus = text("network_running")
        do {
            let domains = networkDNSDomainsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            async let latency = networkDiagnostics.measureLatency(to: latencyURL)
            async let ip = networkDiagnostics.fetchIPGeolocation(from: ipURL)
            async let dns = networkDiagnostics.checkDNSLeak(
                domains: domains.isEmpty ? ["example.com", "apple.com"] : domains,
                expectedCountryCode: networkExpectedCountryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : networkExpectedCountryText
            )
            latencyResult = try await latency
            ipGeolocationResult = try await ip
            dnsLeakResult = try await dns
            networkDiagnosticsStatus = text("network_completed")
        } catch {
            networkDiagnosticsStatus = error.localizedDescription
        }
        isRunningNetworkDiagnostics = false
    }

    func bindSelectedVPNNodeToScenario() {
        guard let node = selectedVPNNode else {
            networkDiagnosticsStatus = text("network_select_vpn_node")
            return
        }

        let domains = networkDNSDomainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let expectedCountry = networkExpectedCountryText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var scenario = selectedScenario
        scenario.networkProfile = NetworkProfile(
            name: node.displayName,
            regionCode: node.regionCode,
            vpnNode: node,
            expectedCountryCode: expectedCountry.isEmpty ? node.regionCode : expectedCountry,
            dnsTestDomains: domains.isEmpty ? ["example.com", "apple.com"] : domains
        )
        scenario.expectedTelemetryTags["vpn_region"] = node.regionCode
        scenario.expectedTelemetryTags["vpn_node_id"] = node.id
        selectedScenario = scenario
        networkExpectedCountryText = scenario.networkProfile?.expectedCountryCode ?? ""
        networkDiagnosticsStatus = text("network_bound_to_scenario")
        exportedJSON = ""
    }

    func addRecentLocation(_ location: SavedMapLocation) {
        var values = recentLocations.filter { !$0.matches(location) }
        values.insert(location, at: 0)
        recentLocations = Array(values.prefix(10))
        Self.saveLocations(recentLocations, forKey: Self.recentLocationsDefaultsKey)
    }

    func addFavoriteLocation(_ location: SavedMapLocation) {
        guard !favoriteLocations.contains(where: { $0.matches(location) }) else {
            return
        }
        favoriteLocations.insert(location, at: 0)
        Self.saveLocations(favoriteLocations, forKey: Self.favoriteLocationsDefaultsKey)
    }

    func removeFavoriteLocation(_ location: SavedMapLocation) {
        favoriteLocations.removeAll { $0.id == location.id || $0.matches(location) }
        Self.saveLocations(favoriteLocations, forKey: Self.favoriteLocationsDefaultsKey)
    }

    func favoriteLocationForCurrentCoordinate() {
        guard let coordinate = manualDeviceLocationCoordinate else {
            developerDeviceStatus = text("developer_devices_invalid_coordinate")
            return
        }
        addFavoriteLocation(
            SavedMapLocation(
                title: String(format: text("custom_coordinate_title"), coordinate.latitude, coordinate.longitude),
                subtitle: text("favorite_location"),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
        developerDeviceStatus = text("favorite_added")
    }

    private static func loadLocations(forKey key: String) -> [SavedMapLocation] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([SavedMapLocation].self, from: data)) ?? []
    }

    private static func saveLocations(_ locations: [SavedMapLocation], forKey key: String) {
        let data = try? JSONEncoder().encode(locations)
        UserDefaults.standard.set(data, forKey: key)
    }

    var selectedDevice: DeveloperDevice? {
        developerDevices.first { $0.id == selectedDeveloperDeviceID }
    }

    func text(_ key: String) -> String {
        StudioLocalizations.text(key, language: language)
    }

    func pointLabel(_ index: Int) -> String {
        "\(text("point")) \(index)"
    }
}

enum StudioLanguage: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        }
    }
}

enum StudioSidebarSelection: Hashable {
    case scenario(String)
    case developerDevices
    case network
    case settings
}

enum StudioModule: String, CaseIterable, Identifiable {
    case scenarios
    case developerDevices
    case network
    case settings

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .scenarios:
            "map"
        case .developerDevices:
            "iphone.gen3"
        case .network:
            "network"
        case .settings:
            "gearshape"
        }
    }

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        switch self {
        case .scenarios:
            store.text("scenarios")
        case .developerDevices:
            store.text("developer_devices")
        case .network:
            store.text("network")
        case .settings:
            store.text("settings")
        }
    }
}

enum RouteMapMode: String, CaseIterable, Identifiable {
    case straightLine
    case roadPlanning

    var id: String { rawValue }

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        switch self {
        case .straightLine:
            store.text("route_mode_straight")
        case .roadPlanning:
            store.text("route_mode_road")
        }
    }
}

enum StudioLocalizations {
    static func text(_ key: String, language: StudioLanguage) -> String {
        switch language {
        case .english:
            english[key] ?? key
        case .simplifiedChinese:
            simplifiedChinese[key] ?? english[key] ?? key
        }
    }

    private static let english: [String: String] = [
        "app_title": "Telemetry Scenario Studio",
        "scenarios": "Scenarios",
        "settings": "Settings",
        "network": "Network",
        "diagnostics": "Diagnostics",
        "developer_devices": "Developer Devices",
        "developer_devices_title": "Developer Devices",
        "developer_devices_description": "List trusted Apple developer devices and set simulator or physical device GPS locations.",
        "refresh": "Refresh",
        "refreshing": "Refreshing...",
        "searching": "Searching...",
        "device": "Device",
        "kind": "Kind",
        "platform": "Platform",
        "model": "Model",
        "status": "Status",
        "source": "Source",
        "coordinate": "Coordinate",
        "progress": "Progress",
        "pairing": "Pairing",
        "hostname": "Hostname",
        "location_control": "Location Control",
        "location_map_picker": "Map Picker",
        "location_map_hint": "Click the map to choose a GPS coordinate, then apply it to the selected device.",
        "location_search": "Search location",
        "location_search_placeholder": "Search address, place, or POI",
        "location_search_no_results": "No results.",
        "center_map": "Center Map",
        "use_scenario_start": "Use Scenario Start",
        "set_location": "Set Location",
        "clear_location": "Clear Location",
        "location_capability": "Capability",
        "available": "Available",
        "unavailable": "Unavailable",
        "trusted_physical_note": "Simulator uses simctl. iOS 17+ physical devices use CoreDevice DVT location simulation through the local pymobiledevice3 runtime, so Xcode does not need to be opened.",
        "xcode_debug_session": "Device Location Simulation",
        "xcode_debug_description": "Applies the selected scenario location directly to the selected developer device without opening Xcode.",
        "generate_debug_gpx": "Generate GPX",
        "start_debug_session": "Apply To Device",
        "generated_gpx": "Generated GPX",
        "xcode_destination_set": "Xcode destination set from selected device.",
        "xcode_gpx_generated": "Generated GPX: %@\nUpdated scheme: %@",
        "xcode_debug_started": "Set %@ location to %.6f, %.6f.",
        "xcode_physical_note": "For now this applies the first point of the scenario. Continuous route playback can be implemented by pushing each route point on a timer through the same device service.",
        "xcode_auto_summary": "Device: %@\nScenario: %@",
        "current_location_status": "Current Location Status",
        "target_device": "Target Device",
        "location_source": "Source",
        "status_time": "Applied At",
        "scenario": "Scenario",
        "route_progress": "Route Progress",
        "playback_options": "Playback",
        "playback_state_idle": "Idle",
        "playback_state_running": "Running",
        "playback_state_paused": "Paused",
        "playback_state_completed": "Completed",
        "playback_state_failed": "Failed",
        "location_source_none": "None",
        "location_source_manual": "Manual",
        "location_source_scenarioStart": "Scenario Start",
        "location_source_scenarioPlayback": "Scenario Playback",
        "location_source_gpxPlayback": "GPX Playback",
        "location_source_cleared": "Cleared",
        "route_playback": "Route Playback",
        "route_playback_summary": "%@ · %d route points",
        "playback_speed": "Speed",
        "loop_playback": "Loop",
        "loop_on": "Loop on",
        "loop_off": "Loop off",
        "play_route": "Play Route",
        "pause_route": "Pause",
        "resume_route": "Resume",
        "stop_route": "Stop",
        "playback_device_unavailable": "The selected device cannot receive simulated locations.",
        "playback_route_empty": "The selected scenario has no route points.",
        "playback_paused": "Route playback paused.",
        "playback_resumed": "Route playback resumed.",
        "playback_completed": "Route playback completed.",
        "playback_applied_point": "Applied point %d of %d to %@.",
        "search_pane_results": "Results",
        "search_pane_recent": "Recent",
        "search_pane_favorites": "Favorites",
        "search_pane_presets": "Presets",
        "recent_locations_empty": "No recent locations.",
        "favorite_locations_empty": "No favorite locations.",
        "add_favorite": "Add Favorite",
        "remove_favorite": "Remove Favorite",
        "favorite_location": "Favorite location",
        "favorite_added": "Favorite location added.",
        "custom_coordinate_title": "%.6f, %.6f",
        "preset_cities": "Cities",
        "preset_airports": "Airports",
        "preset_boundaries": "Boundaries",
        "parameterized_templates": "Parameterized Templates",
        "parameterized_templates_description": "Generate a QA scenario from start/end coordinates, speed, and dwell times.",
        "template_type": "Template Type",
        "template_kind_delivery": "Delivery",
        "template_kind_crossCity": "Cross City",
        "template_kind_fitness": "Fitness",
        "template_kind_tunnelDrift": "Tunnel Drift",
        "template_name_delivery": "Generated Delivery Route",
        "template_name_crossCity": "Generated Cross City",
        "template_name_fitness": "Generated Fitness Route",
        "template_name_tunnelDrift": "Generated Tunnel Drift",
        "template_description_delivery": "Parameterized pickup and drop-off telemetry scenario.",
        "template_description_crossCity": "Parameterized long-distance city movement scenario.",
        "template_description_fitness": "Parameterized walking/running telemetry scenario.",
        "template_description_tunnelDrift": "Parameterized route with a low-signal tunnel marker.",
        "template_delivery_stop": "Stop %d",
        "template_cross_city_segment": "Segment %d",
        "template_fitness_marker": "Marker %d",
        "template_tunnel_low_signal": "Low Signal",
        "template_start": "Start",
        "template_end": "End",
        "template_timing": "Timing",
        "template_speed_mps": "Speed m/s",
        "template_start_dwell": "Start dwell s",
        "template_end_dwell": "End dwell s",
        "use_current_picker": "Use Current",
        "generate_template_route": "Generate Route",
        "generating": "Generating...",
        "template_invalid_parameters": "Enter valid start, end, speed, and dwell values.",
        "play_gpx_to_device": "Play GPX To Device",
        "stop_gpx_playback": "Stop GPX",
        "gpx_playback_status": "GPX Playback Status",
        "gpx_playback_running": "GPX playback is running.",
        "gpx_playback_stopped": "GPX playback stopped.",
        "gpx_playback_completed": "GPX playback completed.",
        "gpx_playback_applied_point": "Applied GPX point %d of %d.",
        "gpx_state_idle": "Idle",
        "gpx_state_running": "Running",
        "gpx_state_stopped": "Stopped",
        "gpx_state_completed": "Completed",
        "gpx_state_failed": "Failed",
        "device_health_check": "Device Health Check",
        "refresh_health_check": "Refresh Health Check",
        "checking": "Checking...",
        "health_check_empty": "Select a device and refresh to inspect pairing, tunnel, DDI, and runtime readiness.",
        "health_checked_at": "Checked at %@",
        "health_checked_at_short": "Checked",
        "blocking_failures": "Blocking Failures",
        "copy_markdown_report": "Copy Markdown",
        "copy_json_report": "Copy JSON",
        "health_report_copied": "Health report copied.",
        "health_status_pass": "Pass",
        "health_status_warn": "Warn",
        "health_status_fail": "Fail",
        "health_status_unknown": "Unknown",
        "active_simulation_title": "Simulated location is active",
        "active_simulation_summary": "Device: %@ · Source: %@ · Coordinate: %@",
        "clear_simulation_now": "Clear Simulation",
        "active_simulation_exit_title": "Simulated location is still active",
        "active_simulation_exit_body": "Clear the selected device location before quitting so QA devices do not stay in a simulated state.",
        "clear_and_quit": "Clear and Quit",
        "quit_without_clearing": "Quit Without Clearing",
        "active_simulation_switch_title": "Simulated location is active",
        "active_simulation_switch_body": "Switching device or scenario while simulation is active can leave the previous device at the last simulated coordinate.",
        "clear_and_continue": "Clear and Continue",
        "continue_without_clearing": "Continue Without Clearing",
        "global_clear_select_device_first": "Select the device shown in the global simulation bar before clearing its simulated location.",
        "cancel": "Cancel",
        "scenario_library": "Scenario Library",
        "scenario_library_description": "Manage local scenarios, recent opens, import/export, copies, names, and deletion.",
        "new_scenario": "New Scenario",
        "new_scenario_description": "Empty QA scenario created in the local library.",
        "scenario_name": "Scenario name",
        "rename_scenario": "Rename",
        "duplicate_scenario": "Duplicate",
        "delete_scenario": "Delete",
        "reset_templates": "Reset Templates",
        "import_scenario_file": "Import File",
        "export_scenario_file": "Export File",
        "scenario_search": "Search scenarios",
        "scenario_tag_filter": "Tag filter",
        "all_tags": "All Tags",
        "scenario_tags": "Tags",
        "tag_key": "Tag key",
        "tag_value": "Tag value",
        "add_tag": "Add Tag",
        "scenario_exported_to": "Exported scenario to %@.",
        "scenario_imported_count": "Imported %d scenario(s).",
        "scenario_autosaved": "Auto-saved %d scenario(s) to the local library.",
        "scenario_loaded_count": "Loaded %d scenario(s) from the local library.",
        "recent_scenarios": "Recent Scenarios",
        "scenario_copy_name": "%@ Copy",
        "scenario_name_required": "Scenario name cannot be empty.",
        "scenario_delete_last_error": "Keep at least one scenario in the local library.",
        "route_timeline": "Route Timeline",
        "timeline_preview_coordinate": "Preview %.6f, %.6f",
        "segment": "Segment",
        "network_description": "Configure target-device VPN metadata for scenarios, then run Mac-local diagnostics for comparison. The iPhone exit IP changes only when Telemetry QA Console connects VPN on that iPhone.",
        "vpn_nodes": "VPN Nodes",
        "target_vpn_notice": "Target-device IP changes are applied by the iOS QA Console on the iPhone. This Studio page binds the node to scenario JSON and previews telemetry fields.",
        "bind_vpn_to_scenario": "Bind VPN to Scenario",
        "network_select_vpn_node": "Select a VPN node first.",
        "network_bound_to_scenario": "VPN node bound to the current scenario. Export JSON and import it in Telemetry QA Console.",
        "kill_switch": "Kill Switch",
        "kill_switch_on": "Kill switch on",
        "kill_switch_enabled_note": "When enabled, QA should block telemetry workflows if VPN connectivity drops. This panel records readiness; Packet Tunnel enforcement remains a later phase.",
        "kill_switch_disabled_note": "Kill switch is disabled. VPN disconnects will not block telemetry workflows in this QA console.",
        "network_endpoints": "Network Endpoints",
        "latency_endpoint": "Latency endpoint",
        "ip_endpoint": "IP endpoint",
        "dns_domains": "DNS domains",
        "expected_country": "Expected country",
        "run_network_diagnostics": "Run Diagnostics",
        "network_running": "Running...",
        "network_completed": "Network diagnostics completed.",
        "network_invalid_endpoints": "Enter valid latency and IP endpoints.",
        "network_results": "Network Results",
        "latency": "Latency",
        "public_ip": "Public IP",
        "dns_leak": "DNS Leak",
        "status_code": "Status Code",
        "country": "Country",
        "tested_domains": "Tested Domains",
        "leak_detected": "Leak detected",
        "no_leak_detected": "No leak detected",
        "telemetry_preview": "Telemetry Preview",
        "telemetry_preview_description": "Read-only payload preview for QA. This does not send data to production telemetry.",
        "copy_fields": "Copy Fields",
        "copy_json": "Copy JSON",
        "copy_device_json": "Copy Device JSON",
        "scenario_payload_json": "Scenario Payload JSON",
        "device_payload_json": "Device State Payload JSON",
        "telemetry_json_copied": "Telemetry JSON copied.",
        "telemetry_fields_copied": "Telemetry fields copied.",
        "automatic": "Automatic",
        "developer_devices_found": "Found %d developer devices.",
        "developer_devices_select_first": "Select a device first.",
        "developer_devices_invalid_coordinate": "Enter a valid latitude and longitude.",
        "developer_devices_location_set": "Location set.",
        "developer_devices_location_cleared": "Location cleared.",
        "settings_title": "Settings",
        "language": "Language",
        "language_description": "Switch the app interface language without restarting.",
        "current_language": "Current language",
        "about": "About",
        "about_body": "Internal QA tool for visual route editing, GPX export, scenario JSON, and MapKit route planning.",
        "points_count": "%d points",
        "add_point": "Add Point",
        "export_gpx": "Export GPX",
        "export_json": "Export JSON",
        "map": "Map",
        "fit_route": "Fit Route",
        "route_mode": "Route Mode",
        "route_mode_straight": "Manual Straight",
        "route_mode_road": "Road Planning",
        "swap_endpoints": "Swap Start/End",
        "planned_route_stale": "Route points changed. Re-run road planning to refresh the green route.",
        "route_swap_needs_two_points": "Add at least two route points before swapping endpoints.",
        "route_keep_one_point": "Keep at least one route point.",
        "total_distance": "Distance",
        "total_duration": "Duration",
        "average_speed": "Avg Speed",
        "points": "Points",
        "total_dwell": "Dwell Total",
        "planning": "Planning...",
        "plan_route": "Plan Route",
        "apply_planned_route": "Apply Planned Route",
        "map_hint_add": "Click map to add a route point",
        "map_hint_drag": "Drag points to adjust route",
        "map_hint_delete": "Right-click a point to delete",
        "map_hint_blue": "Blue is scenario route",
        "map_hint_green": "Green is planned MapKit route",
        "route": "Route",
        "label": "Label",
        "latitude": "Latitude",
        "longitude": "Longitude",
        "speed": "Speed",
        "elapsed": "Elapsed",
        "dwell": "Dwell",
        "remove": "Remove",
        "scenario_json": "Scenario JSON",
        "import_json": "Import JSON",
        "import_scenario": "Import Scenario",
        "point": "Point",
        "start": "Start",
        "end": "End",
        "error_route_needs_two_points": "Add at least two route points before planning.",
        "error_plan_before_apply": "Plan a route before applying it."
    ]

    private static let simplifiedChinese: [String: String] = [
        "app_title": "遥测场景工作台",
        "scenarios": "场景",
        "settings": "设置",
        "network": "网络",
        "diagnostics": "诊断",
        "developer_devices": "开发设备",
        "developer_devices_title": "开发设备",
        "developer_devices_description": "列出受信任 Apple 开发设备，并设置模拟器或真机 GPS 位置。",
        "refresh": "刷新",
        "refreshing": "刷新中...",
        "searching": "搜索中...",
        "device": "设备",
        "kind": "类型",
        "platform": "平台",
        "model": "型号",
        "status": "状态",
        "source": "来源",
        "coordinate": "坐标",
        "progress": "进度",
        "pairing": "配对",
        "hostname": "主机名",
        "location_control": "定位控制",
        "location_map_picker": "地图选点",
        "location_map_hint": "点击地图选择 GPS 坐标，然后应用到选中的设备。",
        "location_search": "搜索位置",
        "location_search_placeholder": "搜索地址、地点或 POI",
        "location_search_no_results": "无搜索结果。",
        "center_map": "居中地图",
        "use_scenario_start": "使用场景起点",
        "set_location": "设置定位",
        "clear_location": "清除定位",
        "location_capability": "能力",
        "available": "可用",
        "unavailable": "不可用",
        "trusted_physical_note": "模拟器使用 simctl。iOS 17+ 真机使用 CoreDevice DVT 定位模拟和本地 pymobiledevice3 运行时，不需要打开 Xcode。",
        "xcode_debug_session": "设备定位模拟",
        "xcode_debug_description": "直接把选中场景的位置应用到选中的开发设备，不打开 Xcode。",
        "generate_debug_gpx": "生成 GPX",
        "start_debug_session": "应用到设备",
        "generated_gpx": "已生成 GPX",
        "xcode_destination_set": "已从选中设备设置 Xcode destination。",
        "xcode_gpx_generated": "已生成 GPX：%@\n已更新 Scheme：%@",
        "xcode_debug_started": "已将 %@ 定位设置为 %.6f, %.6f。",
        "xcode_physical_note": "当前先应用场景第一个路线点。连续路线回放可以继续用同一个设备服务按定时器逐点推送。",
        "xcode_auto_summary": "设备：%@\n场景：%@",
        "current_location_status": "当前位置状态",
        "target_device": "目标设备",
        "location_source": "来源",
        "status_time": "应用时间",
        "scenario": "场景",
        "route_progress": "路线进度",
        "playback_options": "回放",
        "playback_state_idle": "空闲",
        "playback_state_running": "运行中",
        "playback_state_paused": "已暂停",
        "playback_state_completed": "已完成",
        "playback_state_failed": "失败",
        "location_source_none": "无",
        "location_source_manual": "手动",
        "location_source_scenarioStart": "场景起点",
        "location_source_scenarioPlayback": "场景回放",
        "location_source_gpxPlayback": "GPX 回放",
        "location_source_cleared": "已清除",
        "route_playback": "路线回放",
        "route_playback_summary": "%@ · %d 个路线点",
        "playback_speed": "倍速",
        "loop_playback": "循环",
        "loop_on": "循环开",
        "loop_off": "循环关",
        "play_route": "播放路线",
        "pause_route": "暂停",
        "resume_route": "继续",
        "stop_route": "停止",
        "playback_device_unavailable": "选中的设备无法接收模拟定位。",
        "playback_route_empty": "选中的场景没有路线点。",
        "playback_paused": "路线回放已暂停。",
        "playback_resumed": "路线回放已继续。",
        "playback_completed": "路线回放已完成。",
        "playback_applied_point": "已将第 %d / %d 个点应用到 %@。",
        "search_pane_results": "结果",
        "search_pane_recent": "最近",
        "search_pane_favorites": "收藏",
        "search_pane_presets": "预设",
        "recent_locations_empty": "暂无最近位置。",
        "favorite_locations_empty": "暂无收藏位置。",
        "add_favorite": "添加收藏",
        "remove_favorite": "移除收藏",
        "favorite_location": "收藏位置",
        "favorite_added": "已添加收藏位置。",
        "custom_coordinate_title": "%.6f, %.6f",
        "preset_cities": "常用城市",
        "preset_airports": "机场",
        "preset_boundaries": "边界/跨区点",
        "parameterized_templates": "参数化模板",
        "parameterized_templates_description": "根据起终点、速度和停留时间生成 QA 场景路线。",
        "template_type": "模板类型",
        "template_kind_delivery": "外卖",
        "template_kind_crossCity": "跨城",
        "template_kind_fitness": "运动",
        "template_kind_tunnelDrift": "隧道漂移",
        "template_name_delivery": "生成的外卖路线",
        "template_name_crossCity": "生成的跨城路线",
        "template_name_fitness": "生成的运动路线",
        "template_name_tunnelDrift": "生成的隧道漂移路线",
        "template_description_delivery": "参数化取货和送达遥测场景。",
        "template_description_crossCity": "参数化长距离城市移动场景。",
        "template_description_fitness": "参数化步行/跑步遥测场景。",
        "template_description_tunnelDrift": "带低信号隧道标记的参数化路线。",
        "template_delivery_stop": "停靠点 %d",
        "template_cross_city_segment": "路段 %d",
        "template_fitness_marker": "标记 %d",
        "template_tunnel_low_signal": "低信号",
        "template_start": "起点",
        "template_end": "终点",
        "template_timing": "时间参数",
        "template_speed_mps": "速度 m/s",
        "template_start_dwell": "起点停留 s",
        "template_end_dwell": "终点停留 s",
        "use_current_picker": "使用当前",
        "generate_template_route": "生成路线",
        "generating": "生成中...",
        "template_invalid_parameters": "请输入有效的起点、终点、速度和停留时间。",
        "play_gpx_to_device": "回放 GPX 到设备",
        "stop_gpx_playback": "停止 GPX",
        "gpx_playback_status": "GPX 回放状态",
        "gpx_playback_running": "GPX 回放运行中。",
        "gpx_playback_stopped": "GPX 回放已停止。",
        "gpx_playback_completed": "GPX 回放已完成。",
        "gpx_playback_applied_point": "已应用第 %d / %d 个 GPX 点。",
        "gpx_state_idle": "空闲",
        "gpx_state_running": "运行中",
        "gpx_state_stopped": "已停止",
        "gpx_state_completed": "已完成",
        "gpx_state_failed": "失败",
        "device_health_check": "设备健康检查",
        "refresh_health_check": "刷新健康检查",
        "checking": "检查中...",
        "health_check_empty": "选择设备并刷新，以检查配对、隧道、DDI 和运行时状态。",
        "health_checked_at": "检查时间 %@",
        "health_checked_at_short": "检查时间",
        "blocking_failures": "阻断项",
        "copy_markdown_report": "复制 Markdown",
        "copy_json_report": "复制 JSON",
        "health_report_copied": "健康报告已复制。",
        "health_status_pass": "通过",
        "health_status_warn": "警告",
        "health_status_fail": "失败",
        "health_status_unknown": "未知",
        "active_simulation_title": "模拟定位正在生效",
        "active_simulation_summary": "设备：%@ · 来源：%@ · 坐标：%@",
        "clear_simulation_now": "清除模拟",
        "active_simulation_exit_title": "模拟定位仍在生效",
        "active_simulation_exit_body": "退出前建议清除选中设备定位，避免 QA 设备停留在模拟定位状态。",
        "clear_and_quit": "清除并退出",
        "quit_without_clearing": "直接退出",
        "active_simulation_switch_title": "模拟定位正在生效",
        "active_simulation_switch_body": "模拟中切换设备或场景，可能会让前一个设备停留在最后一次模拟坐标。",
        "clear_and_continue": "清除后继续",
        "continue_without_clearing": "保留并继续",
        "global_clear_select_device_first": "请先选择全局状态条中显示的设备，再清除该设备的模拟定位。",
        "cancel": "取消",
        "scenario_library": "场景库",
        "scenario_library_description": "管理本地场景、最近打开、导入导出、复制、重命名和删除。",
        "new_scenario": "新建场景",
        "new_scenario_description": "在本地场景库中新建的空 QA 场景。",
        "scenario_name": "场景名称",
        "rename_scenario": "重命名",
        "duplicate_scenario": "复制",
        "delete_scenario": "删除",
        "reset_templates": "重置模板",
        "import_scenario_file": "导入文件",
        "export_scenario_file": "导出文件",
        "scenario_search": "搜索场景",
        "scenario_tag_filter": "标签筛选",
        "all_tags": "全部标签",
        "scenario_tags": "标签",
        "tag_key": "标签键",
        "tag_value": "标签值",
        "add_tag": "添加标签",
        "scenario_exported_to": "已导出场景到 %@。",
        "scenario_imported_count": "已导入 %d 个场景。",
        "scenario_autosaved": "已自动保存 %d 个场景到本地场景库。",
        "scenario_loaded_count": "已从本地场景库加载 %d 个场景。",
        "recent_scenarios": "最近场景",
        "scenario_copy_name": "%@ 副本",
        "scenario_name_required": "场景名称不能为空。",
        "scenario_delete_last_error": "本地场景库至少需要保留一个场景。",
        "route_timeline": "路线时间轴",
        "timeline_preview_coordinate": "预览 %.6f, %.6f",
        "segment": "路段",
        "network_description": "为场景配置目标设备 VPN 元数据，并运行 Mac 本机诊断作为对比。iPhone 出口 IP 只会在 Telemetry QA Console 于该 iPhone 上连接 VPN 后改变。",
        "vpn_nodes": "VPN 节点",
        "target_vpn_notice": "目标设备 IP 由 iOS QA Console 在 iPhone 上连接 VPN 后生效。本页负责把节点写入场景 JSON，并预览遥测字段。",
        "bind_vpn_to_scenario": "绑定 VPN 到场景",
        "network_select_vpn_node": "请先选择 VPN 节点。",
        "network_bound_to_scenario": "VPN 节点已绑定到当前场景。请导出 JSON 并在 Telemetry QA Console 导入。",
        "kill_switch": "Kill switch",
        "kill_switch_on": "Kill switch 开",
        "kill_switch_enabled_note": "启用后，QA 应在 VPN 断开时阻断遥测流程。当前面板记录就绪状态，Packet Tunnel 强制策略放在后续阶段。",
        "kill_switch_disabled_note": "Kill switch 未启用。VPN 断开不会在此 QA 控制台阻断遥测流程。",
        "network_endpoints": "网络端点",
        "latency_endpoint": "延迟端点",
        "ip_endpoint": "IP 端点",
        "dns_domains": "DNS 域名",
        "expected_country": "期望国家",
        "run_network_diagnostics": "运行诊断",
        "network_running": "运行中...",
        "network_completed": "网络诊断已完成。",
        "network_invalid_endpoints": "请输入有效的延迟和 IP 端点。",
        "network_results": "网络结果",
        "latency": "延迟",
        "public_ip": "公网 IP",
        "dns_leak": "DNS 泄漏",
        "status_code": "状态码",
        "country": "国家",
        "tested_domains": "测试域名",
        "leak_detected": "发现泄漏",
        "no_leak_detected": "未发现泄漏",
        "telemetry_preview": "遥测预览",
        "telemetry_preview_description": "QA 只读 payload 预览，不会发送到生产遥测。",
        "copy_fields": "复制字段",
        "copy_json": "复制 JSON",
        "copy_device_json": "复制设备 JSON",
        "scenario_payload_json": "场景 Payload JSON",
        "device_payload_json": "设备状态 Payload JSON",
        "telemetry_json_copied": "遥测 JSON 已复制。",
        "telemetry_fields_copied": "遥测字段已复制。",
        "automatic": "自动",
        "developer_devices_found": "发现 %d 台开发设备。",
        "developer_devices_select_first": "请先选择设备。",
        "developer_devices_invalid_coordinate": "请输入有效的纬度和经度。",
        "developer_devices_location_set": "定位已设置。",
        "developer_devices_location_cleared": "定位已清除。",
        "settings_title": "设置",
        "language": "语言",
        "language_description": "无需重启即可切换应用界面语言。",
        "current_language": "当前语言",
        "about": "关于",
        "about_body": "企业内部 QA 工具，用于可视化路线编辑、GPX 导出、场景 JSON 和 MapKit 路线规划。",
        "points_count": "%d 个点",
        "add_point": "添加点",
        "export_gpx": "导出 GPX",
        "export_json": "导出 JSON",
        "map": "地图",
        "fit_route": "适配路线",
        "route_mode": "路径模式",
        "route_mode_straight": "手动直线",
        "route_mode_road": "道路规划",
        "swap_endpoints": "互换起终点",
        "planned_route_stale": "路线点已变化，请重新道路规划以刷新绿色路线。",
        "route_swap_needs_two_points": "互换起终点前至少需要两个路线点。",
        "route_keep_one_point": "至少需要保留一个路线点。",
        "total_distance": "总距离",
        "total_duration": "总时长",
        "average_speed": "平均速度",
        "points": "点数",
        "total_dwell": "总停留",
        "planning": "规划中...",
        "plan_route": "规划路线",
        "apply_planned_route": "应用规划路线",
        "map_hint_add": "点击地图添加路线点",
        "map_hint_drag": "拖动点调整路线",
        "map_hint_delete": "右键点位删除",
        "map_hint_blue": "蓝色为场景路线",
        "map_hint_green": "绿色为 MapKit 规划路线",
        "route": "路线",
        "label": "标签",
        "latitude": "纬度",
        "longitude": "经度",
        "speed": "速度",
        "elapsed": "耗时",
        "dwell": "停留",
        "remove": "删除",
        "scenario_json": "场景 JSON",
        "import_json": "导入 JSON",
        "import_scenario": "导入场景",
        "point": "点",
        "start": "起点",
        "end": "终点",
        "error_route_needs_two_points": "规划路线前至少需要添加两个路线点。",
        "error_plan_before_apply": "请先规划路线，再应用规划结果。"
    ]
}

struct MapCoordinate: Identifiable, Sendable {
    var id = UUID()
    var latitude: Double
    var longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationSearchResult: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var subtitle: String
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: LocationSearchResult, rhs: LocationSearchResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum RoutePlaybackState: String, CaseIterable, Identifiable {
    case idle
    case running
    case paused
    case completed
    case failed

    var id: String { rawValue }

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        store.text("playback_state_\(rawValue)")
    }
}

enum DeviceLocationSource: String {
    case none
    case manual
    case scenarioStart
    case scenarioPlayback
    case gpxPlayback
    case cleared

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        store.text("location_source_\(rawValue)")
    }
}

struct DeviceLocationStatusSnapshot {
    var playbackState: RoutePlaybackState = .idle
    var source: DeviceLocationSource = .none
    var deviceName: String?
    var deviceID: String?
    var scenarioName: String?
    var scenarioID: String?
    var coordinate: CLLocationCoordinate2D?
    var appliedAt: Date?
    var pointIndex: Int?
    var totalPoints: Int?
    var playbackSpeed: Double = 1
    var loops = false
}

struct RouteTimelineSegment: Identifiable {
    var id: String
    var index: Int
    var label: String
    var elapsedSeconds: TimeInterval
    var dwellSeconds: TimeInterval
    var segmentSeconds: TimeInterval
    var coordinate: CLLocationCoordinate2D
}

struct SavedMapLocation: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    init(searchResult: LocationSearchResult) {
        self.init(
            title: searchResult.title,
            subtitle: searchResult.subtitle,
            latitude: searchResult.coordinate.latitude,
            longitude: searchResult.coordinate.longitude
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func matches(_ other: SavedMapLocation) -> Bool {
        title.caseInsensitiveCompare(other.title) == .orderedSame &&
            abs(latitude - other.latitude) < 0.000001 &&
            abs(longitude - other.longitude) < 0.000001
    }
}

struct LocationPresetGroup: Identifiable, Hashable {
    var id: String
    var titleKey: String
    var locations: [SavedMapLocation]

    static let defaults: [LocationPresetGroup] = [
        LocationPresetGroup(
            id: "cities",
            titleKey: "preset_cities",
            locations: [
                SavedMapLocation(title: "Shanghai", subtitle: "China", latitude: 31.2304, longitude: 121.4737),
                SavedMapLocation(title: "Beijing", subtitle: "China", latitude: 39.9042, longitude: 116.4074),
                SavedMapLocation(title: "Tokyo", subtitle: "Japan", latitude: 35.6762, longitude: 139.6503),
                SavedMapLocation(title: "New York", subtitle: "United States", latitude: 40.7128, longitude: -74.0060),
                SavedMapLocation(title: "London", subtitle: "United Kingdom", latitude: 51.5072, longitude: -0.1276),
                SavedMapLocation(title: "Singapore", subtitle: "Singapore", latitude: 1.3521, longitude: 103.8198),
                SavedMapLocation(title: "Hong Kong", subtitle: "China", latitude: 22.3193, longitude: 114.1694),
                SavedMapLocation(title: "Los Angeles", subtitle: "United States", latitude: 34.0522, longitude: -118.2437)
            ]
        ),
        LocationPresetGroup(
            id: "airports",
            titleKey: "preset_airports",
            locations: [
                SavedMapLocation(title: "JFK", subtitle: "New York John F. Kennedy International Airport", latitude: 40.6413, longitude: -73.7781),
                SavedMapLocation(title: "LAX", subtitle: "Los Angeles International Airport", latitude: 33.9416, longitude: -118.4085),
                SavedMapLocation(title: "PVG", subtitle: "Shanghai Pudong International Airport", latitude: 31.1443, longitude: 121.8083),
                SavedMapLocation(title: "PEK", subtitle: "Beijing Capital International Airport", latitude: 40.0799, longitude: 116.6031)
            ]
        ),
        LocationPresetGroup(
            id: "boundaries",
            titleKey: "preset_boundaries",
            locations: [
                SavedMapLocation(title: "Shenzhen / Hong Kong", subtitle: "Boundary crossing QA point", latitude: 22.5319, longitude: 114.1131),
                SavedMapLocation(title: "Macau / Zhuhai", subtitle: "Boundary crossing QA point", latitude: 22.1987, longitude: 113.5439),
                SavedMapLocation(title: "San Diego / Tijuana", subtitle: "US/MX boundary QA point", latitude: 32.5445, longitude: -117.0308)
            ]
        )
    ]
}

enum LocationSearchPane: String, CaseIterable, Identifiable {
    case results
    case recent
    case favorites
    case presets

    var id: String { rawValue }

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        store.text("search_pane_\(rawValue)")
    }
}

enum ParameterizedScenarioKind: String, CaseIterable, Identifiable {
    case delivery
    case crossCity
    case fitness
    case tunnelDrift

    var id: String { rawValue }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .fitness:
            .walking
        case .delivery, .crossCity, .tunnelDrift:
            .automobile
        }
    }

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        store.text("template_kind_\(rawValue)")
    }

    @MainActor
    func scenarioName(in store: ScenarioStudioStore) -> String {
        store.text("template_name_\(rawValue)")
    }

    @MainActor
    func scenarioDescription(in store: ScenarioStudioStore) -> String {
        store.text("template_description_\(rawValue)")
    }

    @MainActor
    func pointLabel(index: Int, total: Int, in store: ScenarioStudioStore) -> String? {
        if index == 0 {
            return store.text("start")
        }
        if index == total - 1 {
            return store.text("end")
        }
        switch self {
        case .delivery:
            return String(format: store.text("template_delivery_stop"), index)
        case .crossCity:
            return String(format: store.text("template_cross_city_segment"), index)
        case .fitness:
            return String(format: store.text("template_fitness_marker"), index)
        case .tunnelDrift:
            return index == total / 2 ? store.text("template_tunnel_low_signal") : nil
        }
    }
}

enum GPXPlaybackRunState: String {
    case idle
    case running
    case stopped
    case completed
    case failed

    @MainActor
    func title(in store: ScenarioStudioStore) -> String {
        store.text("gpx_state_\(rawValue)")
    }
}

struct GPXPlaybackStatus {
    var state: GPXPlaybackRunState = .idle
    var deviceName: String?
    var scenarioName: String?
    var currentIndex: Int = 0
    var totalPoints: Int = 0
    var lastCoordinate: CLLocationCoordinate2D?
    var message: String?
}

struct GPXTrackPoint {
    var coordinate: CLLocationCoordinate2D
    var timestamp: Date
}

final class GPXTrackPointParser: NSObject, XMLParserDelegate {
    private var points: [GPXTrackPoint] = []
    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentTimeText = ""
    private var isReadingTime = false
    private let dateFormatter = ISO8601DateFormatter()

    static func parse(_ gpx: String) throws -> [GPXTrackPoint] {
        let parserDelegate = GPXTrackPointParser()
        let parser = XMLParser(data: Data(gpx.utf8))
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw parser.parserError ?? ScenarioStudioError.invalidGPX
        }
        return parserDelegate.points
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "trkpt":
            currentLatitude = attributeDict["lat"].flatMap(Double.init)
            currentLongitude = attributeDict["lon"].flatMap(Double.init)
            currentTimeText = ""
        case "time":
            isReadingTime = currentLatitude != nil && currentLongitude != nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingTime {
            currentTimeText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "time":
            isReadingTime = false
        case "trkpt":
            if let latitude = currentLatitude,
               let longitude = currentLongitude,
               let timestamp = dateFormatter.date(from: currentTimeText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if CLLocationCoordinate2DIsValid(coordinate) {
                    points.append(GPXTrackPoint(coordinate: coordinate, timestamp: timestamp))
                }
            }
            currentLatitude = nil
            currentLongitude = nil
            currentTimeText = ""
            isReadingTime = false
        default:
            break
        }
    }
}

enum ScenarioStudioError: LocalizedError {
    case noRouteFound
    case invalidGPX
    case emptyGPXTrack

    var errorDescription: String? {
        switch self {
        case .noRouteFound:
            "MapKit did not return a route for the selected points."
        case .invalidGPX:
            "Unable to parse the generated GPX."
        case .emptyGPXTrack:
            "The generated GPX does not contain track points."
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var values = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
        return values
    }
}

struct ScenarioStudioView: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        HStack(spacing: 0) {
            EmbeddedStudioSidebar(store: store)
                .frame(width: 244)
                .background(StudioVisualEffectBackground(material: .sidebar))

            Divider()
                .opacity(0.45)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var detail: some View {
        switch store.sidebarSelection {
        case .developerDevices:
            contentWithSimulationBanner {
                DeveloperDevicesView(store: store)
            }
        case .network:
            contentWithSimulationBanner {
                NetworkDiagnosticsView(store: store)
            }
        case .settings:
            contentWithSimulationBanner {
                SettingsView(store: store)
            }
        default:
            contentWithSimulationBanner {
                ScenarioEditorView(store: store)
            }
        }
    }

    private func contentWithSimulationBanner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            GlobalSimulationStatusBar(store: store)
            content()
        }
    }
}

struct EmbeddedStudioSidebar: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            sidebarSection(store.text("scenarios"))

            ForEach(store.filteredScenarios) { scenario in
                StudioSidebarRow(
                    title: scenario.name,
                    subtitle: String(format: store.text("points_count"), scenario.route.count),
                    systemImage: "map",
                    isSelected: store.sidebarSelection == .scenario(scenario.id)
                ) {
                    store.selectSidebar(.scenario(scenario.id))
                }
            }

            sidebarSection(store.text("location_control"))

            StudioSidebarRow(
                title: store.text("developer_devices"),
                subtitle: store.selectedDevice?.name ?? store.text("automatic"),
                systemImage: "iphone.gen3",
                isSelected: store.sidebarSelection == .developerDevices
            ) {
                store.selectSidebar(.developerDevices)
            }

            StudioSidebarRow(
                title: store.text("network"),
                subtitle: store.killSwitchEnabled ? store.text("kill_switch_on") : store.text("diagnostics"),
                systemImage: "network",
                isSelected: store.sidebarSelection == .network
            ) {
                store.selectSidebar(.network)
            }

            Spacer(minLength: 0)

            StudioSidebarRow(
                title: store.text("settings"),
                subtitle: store.language.displayName,
                systemImage: "gearshape",
                isSelected: store.sidebarSelection == .settings
            ) {
                store.selectSidebar(.settings)
            }
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        }
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 5)
    }
}

struct StudioSidebarRow: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, subtitle == nil ? 7 : 6)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.10))
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.055))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct StudioVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

struct GlobalSimulationStatusBar: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        let status = store.deviceLocationStatus

        HStack(spacing: 14) {
            Image(systemName: store.hasActiveSimulation ? "location.fill" : "location.slash")
                .foregroundStyle(store.hasActiveSimulation ? .orange : .secondary)
                .frame(width: 18)

            statusCell(store.text("device"), status.deviceName ?? store.selectedDevice?.name ?? store.text("automatic"))
            statusCell(store.text("status"), status.playbackState.title(in: store))
            statusCell(store.text("scenario"), status.scenarioName ?? store.selectedScenario.name)
            statusCell(store.text("source"), status.source.title(in: store))
            statusCell(store.text("coordinate"), coordinateText(status.coordinate))
            statusCell(store.text("progress"), progressText(status))

            Spacer()

            Text(lastAppliedText(status.appliedAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(store.text("clear_simulation_now")) {
                Task { await store.clearGlobalSimulationStatus() }
            }
            .disabled(!store.hasActiveSimulation)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(store.hasActiveSimulation ? Color.orange.opacity(0.10) : Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private func statusCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
        }
        .frame(minWidth: 76, alignment: .leading)
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else {
            return "-"
        }
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func progressText(_ status: DeviceLocationStatusSnapshot) -> String {
        guard let pointIndex = status.pointIndex, let total = status.totalPoints, total > 0 else {
            return "-"
        }
        return "\(pointIndex + 1)/\(total)"
    }

    private func lastAppliedText(_ date: Date?) -> String {
        guard let date else {
            return "-"
        }
        return date.formatted(date: .omitted, time: .standard)
    }
}

struct DeveloperDevicesView: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.text("developer_devices_title"))
                            .font(.largeTitle.bold())
                        Text(store.text("developer_devices_description"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isRefreshingDeveloperDevices ? store.text("refreshing") : store.text("refresh")) {
                        Task { await store.refreshDeveloperDevices() }
                    }
                    .disabled(store.isRefreshingDeveloperDevices)
                }

                if let status = store.developerDeviceStatus {
                    Text(status)
                        .foregroundStyle(.secondary)
                }

                Text(store.text("trusted_physical_note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: 820, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

                DeviceLocationStatusPanel(store: store)
                DeviceHealthCheckPanel(store: store)
                DeviceListPanel(store: store)
                DeviceLocationControlPanel(store: store)
                XcodeDebugSessionPanel(store: store)
            }
            .padding(.top, 52)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            if store.developerDevices.isEmpty {
                await store.refreshDeveloperDevices()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct DeviceListPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.text("device"))
                .font(.title3.bold())

            if store.developerDevices.isEmpty {
                Text(store.text("developer_devices_found").replacingOccurrences(of: "%d", with: "0"))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text(store.text("device")).bold()
                        Text(store.text("kind")).bold()
                        Text(store.text("platform")).bold()
                        Text(store.text("model")).bold()
                        Text(store.text("status")).bold()
                        Text(store.text("pairing")).bold()
                        Text(store.text("hostname")).bold()
                    }

                    ForEach(store.developerDevices) { device in
                        GridRow {
                            Button(device.name) {
                                store.selectDeveloperDevice(device)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(device.id == store.selectedDeveloperDeviceID ? .orange : .primary)
                            Text(device.kind.rawValue)
                            Text(device.platform)
                            Text(device.model)
                            Text(device.connectionSummary)
                            Text(device.pairingState ?? "-")
                            Text(device.hostname ?? "-")
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct DeviceLocationStatusPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        let status = store.deviceLocationStatus

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.text("current_location_status"), systemImage: "location.circle")
                    .font(.title3.bold())
                Spacer()
                Text(status.playbackState.title(in: store))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor(status.playbackState))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(status.playbackState).opacity(0.14), in: Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    statusCell(store.text("target_device"), status.deviceName ?? store.selectedDevice?.name ?? "-")
                    statusCell(store.text("location_source"), status.source.title(in: store))
                    statusCell(store.text("status_time"), formattedDate(status.appliedAt))
                }
                GridRow {
                    statusCell(store.text("scenario"), status.scenarioName ?? store.selectedScenario.name)
                    statusCell(store.text("route_progress"), progressText(status))
                    statusCell(store.text("playback_options"), optionsText(status))
                }
                GridRow {
                    statusCell(store.text("latitude"), coordinateText(status.coordinate?.latitude))
                    statusCell(store.text("longitude"), coordinateText(status.coordinate?.longitude))
                    statusCell("ID", status.deviceID ?? "-")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func statusCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func coordinateText(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }
        return String(format: "%.6f", value)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "-"
        }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func progressText(_ status: DeviceLocationStatusSnapshot) -> String {
        guard let pointIndex = status.pointIndex, let totalPoints = status.totalPoints else {
            return "-"
        }
        return "\(pointIndex + 1) / \(totalPoints)"
    }

    private func optionsText(_ status: DeviceLocationStatusSnapshot) -> String {
        let loop = status.loops ? store.text("loop_on") : store.text("loop_off")
        return String(format: "%.1fx · %@", status.playbackSpeed, loop)
    }

    private func statusColor(_ state: RoutePlaybackState) -> Color {
        switch state {
        case .idle:
            .secondary
        case .running:
            .green
        case .paused:
            .orange
        case .completed:
            .blue
        case .failed:
            .red
        }
    }
}

struct DeviceHealthCheckPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.text("device_health_check"), systemImage: "stethoscope")
                    .font(.title3.bold())
                Spacer()
                Button(store.isRunningHealthCheck ? store.text("checking") : store.text("refresh_health_check")) {
                    Task { await store.refreshSelectedDeviceHealth() }
                }
                .disabled(store.isRunningHealthCheck || store.selectedDevice == nil)
            }

            if let check = store.deviceHealthCheck {
                HStack(alignment: .top) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            healthSummaryCell(store.text("target_device"), check.deviceName)
                            healthSummaryCell(store.text("status"), healthTitle(check.summaryStatus))
                            healthSummaryCell(store.text("blocking_failures"), "\(check.blockingFailureCount)")
                            healthSummaryCell(store.text("health_checked_at_short"), check.checkedAt.formatted(date: .omitted, time: .standard))
                        }
                    }
                    Spacer()
                    Button(store.text("copy_markdown_report")) {
                        store.copyHealthReportMarkdown()
                    }
                    Button(store.text("copy_json_report")) {
                        store.copyHealthReportJSON()
                    }
                }

                VStack(spacing: 8) {
                    ForEach(check.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: healthIcon(item.status))
                                .foregroundStyle(healthColor(item.status))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(item.title)
                                        .font(.callout.weight(.semibold))
                                    Text(healthTitle(item.status))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(healthColor(item.status))
                                }
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(item.recommendation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let command = item.repairCommand, !command.isEmpty {
                                    Text(command)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .padding(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                Text(store.text("health_check_empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func healthSummaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
    }

    private func healthIcon(_ status: DeviceHealthItem.Status) -> String {
        switch status {
        case .pass:
            "checkmark.circle.fill"
        case .warn:
            "exclamationmark.triangle.fill"
        case .fail:
            "xmark.octagon.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private func healthColor(_ status: DeviceHealthItem.Status) -> Color {
        switch status {
        case .pass:
            .green
        case .warn:
            .orange
        case .fail:
            .red
        case .unknown:
            .secondary
        }
    }

    private func healthTitle(_ status: DeviceHealthItem.Status) -> String {
        store.text("health_status_\(status.rawValue)")
    }
}

struct DeviceLocationControlPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.text("location_control"))
                .font(.title3.bold())

            if let selectedDevice = store.selectedDevice {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDevice.name)
                        .font(.headline)
                    Text("\(store.text("location_capability")): \(capabilityText(selectedDevice))")
                        .foregroundStyle(selectedDevice.locationCapability.isAvailable ? .green : .secondary)
                    if case let .unavailable(reason) = selectedDevice.locationCapability {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    TextField(store.text("latitude"), text: $store.locationLatitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    TextField(store.text("longitude"), text: $store.locationLongitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Button(store.text("set_location")) {
                        Task { await store.setSelectedDeviceLocation() }
                    }
                    .disabled(!selectedDevice.locationCapability.isAvailable)
                    Button(store.text("clear_location")) {
                        Task { await store.clearSelectedDeviceLocation() }
                    }
                    .disabled(!selectedDevice.locationCapability.isAvailable)
                }

                DeviceLocationMapPicker(store: store)
                RoutePlaybackControlPanel(store: store, selectedDevice: selectedDevice)
                RoutePlaybackTimelinePanel(store: store)
            } else {
                Text(store.text("developer_devices_select_first"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func capabilityText(_ device: DeveloperDevice) -> String {
        switch device.locationCapability {
        case .simctl:
            return "simctl location"
        case .dvtCoreDevice:
            return "CoreDevice DVT location"
        case .ideviceSetLocation:
            return "idevicesetlocation"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct DeviceLocationMapPicker: View {
    @Bindable var store: ScenarioStudioStore
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var searchText = ""
    @State private var searchResults: [LocationSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedSearchPane: LocationSearchPane = .results

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.text("location_map_picker"))
                        .font(.headline)
                    Text(store.text("location_map_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.text("use_scenario_start")) {
                    store.useScenarioStartForDeviceLocation()
                    centerOnCurrentCoordinate()
                }
                Button(store.text("center_map")) {
                    centerOnCurrentCoordinate()
                }
                .disabled(store.manualDeviceLocationCoordinate == nil)
                Button(store.text("add_favorite")) {
                    store.favoriteLocationForCurrentCoordinate()
                }
                .disabled(store.manualDeviceLocationCoordinate == nil)
            }

            HStack(spacing: 8) {
                TextField(store.text("location_search_placeholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await searchLocation() }
                    }

                Button(isSearching ? store.text("searching") : store.text("location_search")) {
                    Task { await searchLocation() }
                }
                .disabled(isSearching || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(store.text("location_search"), selection: $selectedSearchPane) {
                ForEach(LocationSearchPane.allCases) { pane in
                    Text(pane.title(in: store)).tag(pane)
                }
            }
            .pickerStyle(.segmented)

            locationList
                .frame(maxHeight: 230)

            MapReader { proxy in
                Map(position: $position) {
                    if let coordinate = store.manualDeviceLocationCoordinate {
                        Annotation(store.text("set_location"), coordinate: coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 20, height: 20)
                            }
                            .shadow(radius: 2)
                        }
                    }

                    if store.selectedScenario.route.count >= 2 {
                        MapPolyline(coordinates: store.selectedScenario.route.map(\.coordinate))
                            .stroke(.blue.opacity(0.65), lineWidth: 3)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        store.updateManualDeviceLocation(coordinate)
                    }
                }
                .onAppear {
                    centerOnCurrentCoordinate()
                }
            }
        }
    }

    @ViewBuilder
    private var locationList: some View {
        switch selectedSearchPane {
        case .results:
            savedLocationList(
                locations: searchResults.map(SavedMapLocation.init(searchResult:)),
                emptyText: store.text("location_search_no_results"),
                showsFavoriteActions: true
            )
        case .recent:
            savedLocationList(
                locations: store.recentLocations,
                emptyText: store.text("recent_locations_empty"),
                showsFavoriteActions: true
            )
        case .favorites:
            savedLocationList(
                locations: store.favoriteLocations,
                emptyText: store.text("favorite_locations_empty"),
                showsFavoriteActions: false,
                showsRemoveFavorite: true
            )
        case .presets:
            presetLocationList
        }
    }

    private func savedLocationList(
        locations: [SavedMapLocation],
        emptyText: String,
        showsFavoriteActions: Bool,
        showsRemoveFavorite: Bool = false
    ) -> some View {
        ScrollView {
            if locations.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(locations) { location in
                        locationRow(
                            location,
                            showsFavoriteAction: showsFavoriteActions,
                            showsRemoveFavorite: showsRemoveFavorite
                        )

                        if location.id != locations.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private var presetLocationList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.presetLocationGroups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.text(group.titleKey))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                        ForEach(group.locations) { location in
                            locationRow(location, showsFavoriteAction: true)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func locationRow(
        _ location: SavedMapLocation,
        showsFavoriteAction: Bool,
        showsRemoveFavorite: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                selectSavedLocation(location)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mappin.circle")
                        .foregroundStyle(.orange)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(location.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if !location.subtitle.isEmpty {
                            Text(location.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text("\(location.latitude, format: .number.precision(.fractionLength(4))), \(location.longitude, format: .number.precision(.fractionLength(4)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsFavoriteAction {
                Button {
                    store.addFavoriteLocation(location)
                } label: {
                    Image(systemName: "star")
                }
                .buttonStyle(.borderless)
                .help(store.text("add_favorite"))
            }

            if showsRemoveFavorite {
                Button {
                    store.removeFavoriteLocation(location)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(store.text("remove_favorite"))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    private func centerOnCurrentCoordinate() {
        guard let coordinate = store.manualDeviceLocationCoordinate else {
            return
        }
        position = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
    }

    @MainActor
    private func searchLocation() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }

        isSearching = true
        searchError = nil

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let coordinate = store.manualDeviceLocationCoordinate {
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
                )
            }

            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems.prefix(8).map { item in
                let subtitleParts = [item.placemark.title, item.placemark.country]
                    .compactMap { $0 }
                let subtitle = subtitleParts.reduce(into: [String]()) { values, value in
                    if !values.contains(value) {
                        values.append(value)
                    }
                }

                return LocationSearchResult(
                    title: item.name ?? query,
                    subtitle: subtitle.joined(separator: " · "),
                    coordinate: item.placemark.coordinate
                )
            }
            if searchResults.isEmpty {
                searchError = store.text("location_search_no_results")
            }
            selectedSearchPane = .results
        } catch {
            searchError = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    private func selectSavedLocation(_ location: SavedMapLocation) {
        store.updateManualDeviceLocation(location.coordinate)
        store.addRecentLocation(location)
        searchText = location.title
        position = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )
    }
}

struct RoutePlaybackControlPanel: View {
    @Bindable var store: ScenarioStudioStore
    var selectedDevice: DeveloperDevice

    private let speeds: [Double] = [0.5, 1, 2, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label(store.text("route_playback"), systemImage: "play.circle")
                    .font(.headline)
                Spacer()
                Picker(store.text("playback_speed"), selection: $store.routePlaybackSpeed) {
                    ForEach(speeds, id: \.self) { speed in
                        Text(String(format: "%.1fx", speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Toggle(store.text("loop_playback"), isOn: $store.routePlaybackLoops)
                    .toggleStyle(.switch)
            }

            Text(String(format: store.text("route_playback_summary"), store.selectedScenario.name, store.selectedScenario.route.count))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(store.text("play_route")) {
                    store.startRoutePlayback()
                }
                .disabled(!selectedDevice.locationCapability.isAvailable || store.selectedScenario.route.isEmpty || store.routePlaybackState == .running)

                Button(store.text("pause_route")) {
                    store.pauseRoutePlayback()
                }
                .disabled(store.routePlaybackState != .running)

                Button(store.text("resume_route")) {
                    store.resumeRoutePlayback()
                }
                .disabled(store.routePlaybackState != .paused)

                Button(store.text("stop_route")) {
                    store.stopRoutePlayback()
                }
                .disabled(store.routePlaybackState == .idle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct RoutePlaybackTimelinePanel: View {
    @Bindable var store: ScenarioStudioStore
    private let speeds: [Double] = [0.5, 1, 2, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label(store.text("route_timeline"), systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Picker(store.text("playback_speed"), selection: $store.routePlaybackSpeed) {
                    ForEach(speeds, id: \.self) { speed in
                        Text(String(format: "%.1fx", speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Toggle(store.text("loop_playback"), isOn: $store.routePlaybackLoops)
                    .toggleStyle(.switch)
            }

            HStack {
                Text(timeText(store.routeTimelineTime))
                    .font(.caption.monospacedDigit())
                Slider(
                    value: Binding(
                        get: { store.routeTimelineTime },
                        set: { store.jumpRoutePlayback(to: $0) }
                    ),
                    in: 0...max(store.routeTimelineDuration, 1)
                )
                Text(timeText(store.routeTimelineDuration))
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 8) {
                Button(store.text("play_route")) {
                    store.startRoutePlayback()
                }
                .disabled(store.selectedDevice?.locationCapability.isAvailable != true || store.selectedScenario.route.isEmpty || store.routePlaybackState == .running)

                Button(store.text("pause_route")) {
                    store.pauseRoutePlayback()
                }
                .disabled(store.routePlaybackState != .running)

                Button(store.text("resume_route")) {
                    store.resumeRoutePlayback()
                }
                .disabled(store.routePlaybackState != .paused)

                Button(store.text("stop_route")) {
                    store.stopRoutePlayback()
                }
                .disabled(store.routePlaybackState == .idle)

                Spacer()

                if let coordinate = store.routeTimelinePreviewCoordinate {
                    Text(String(format: store.text("timeline_preview_coordinate"), coordinate.latitude, coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.routeTimelineSegments) { segment in
                        Button {
                            store.jumpRoutePlayback(to: segment.elapsedSeconds)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(segment.id == store.selectedPointID ? .orange : .secondary)
                                        .frame(width: 8, height: 8)
                                    Text("\(segment.index + 1). \(segment.label)")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                Text(timeText(segment.elapsedSeconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    timelineMetric(store.text("dwell"), segment.dwellSeconds)
                                    timelineMetric(store.text("segment"), segment.segmentSeconds)
                                }
                            }
                            .padding(10)
                            .frame(width: 170, alignment: .leading)
                            .background(segment.id == store.selectedPointID ? Color.orange.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(segment.id == store.selectedPointID ? Color.orange.opacity(0.55) : Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func timelineMetric(_ title: String, _ value: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(timeText(value))
                .font(.caption.monospacedDigit())
        }
    }

    private func timeText(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct XcodeDebugSessionPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ladybug")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.text("xcode_debug_session"))
                        .font(.title3.bold())
                    Text(store.text("xcode_debug_description"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(store.xcodeDebugSummary)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: 520, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(store.text("generate_debug_gpx")) {
                    store.generateXcodeDebugGPX()
                }
                Button(store.text("start_debug_session")) {
                    Task { await store.launchXcodeDebugSession() }
                }
                Button(store.text("play_gpx_to_device")) {
                    store.startGPXPlaybackToDevice()
                }
                .disabled(store.selectedDevice == nil || store.gpxPlaybackState.state == .running)
                Button(store.text("stop_gpx_playback")) {
                    store.stopGPXPlayback()
                }
                .disabled(store.gpxPlaybackState.state != .running)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.text("gpx_playback_status"))
                        .font(.headline)
                    Spacer()
                    Text(store.gpxPlaybackState.state.title(in: store))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gpxStateColor(store.gpxPlaybackState.state))
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        gpxCell(store.text("target_device"), store.gpxPlaybackState.deviceName ?? store.selectedDevice?.name ?? "-")
                        gpxCell(store.text("scenario"), store.gpxPlaybackState.scenarioName ?? store.selectedScenario.name)
                        gpxCell(store.text("route_progress"), "\(store.gpxPlaybackState.currentIndex) / \(store.gpxPlaybackState.totalPoints)")
                    }
                    GridRow {
                        gpxCell(store.text("latitude"), coordinateText(store.gpxPlaybackState.lastCoordinate?.latitude))
                        gpxCell(store.text("longitude"), coordinateText(store.gpxPlaybackState.lastCoordinate?.longitude))
                        gpxCell(store.text("status"), store.gpxPlaybackState.message ?? "-")
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            )

            if let path = store.generatedDebugGPXPath {
                LabeledContent(store.text("generated_gpx")) {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Text(store.text("xcode_physical_note"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = store.xcodeDebugStatus {
                Text(status)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func gpxCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func coordinateText(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }
        return String(format: "%.6f", value)
    }

    private func gpxStateColor(_ state: GPXPlaybackRunState) -> Color {
        switch state {
        case .idle:
            .secondary
        case .running:
            .green
        case .stopped:
            .orange
        case .completed:
            .blue
        case .failed:
            .red
        }
    }
}

struct ScenarioEditorView: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        let scenario = store.selectedScenario

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(scenario.name)
                            .font(.largeTitle.bold())
                        Text(scenario.description)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.text("add_point"), action: store.addPoint)
                    Button(store.text("export_gpx"), action: store.exportGPX)
                    Button(store.text("export_json"), action: store.exportJSON)
                }

                if let error = store.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }

                ScenarioLibraryPanel(store: store)
                ParameterizedTemplatePanel(store: store)
                ScenarioMapPanel(store: store)
                RoutePlaybackTimelinePanel(store: store)
                RoutePointTable(store: store)
                ExportPanel(title: "GPX", text: store.exportedGPX)
                ExportPanel(title: store.text("scenario_json"), text: store.exportedJSON)

                VStack(alignment: .leading) {
                    Text(store.text("import_json"))
                        .font(.headline)
                    TextEditor(text: $store.importText)
                        .frame(height: 140)
                        .border(.separator)
                    Button(store.text("import_scenario"), action: store.importJSON)
                }
            }
            .padding(24)
        }
    }
}

struct ScenarioLibraryPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(store.text("scenario_library"), systemImage: "folder")
                        .font(.headline)
                    Text(store.text("scenario_library_description"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.text("new_scenario")) {
                    store.createScenario()
                }
                Button(store.text("duplicate_scenario")) {
                    store.duplicateSelectedScenario()
                }
                Button(store.text("delete_scenario")) {
                    store.deleteSelectedScenario()
                }
                .disabled(store.scenarios.count <= 1)
                Button(store.text("reset_templates")) {
                    store.resetScenarioLibraryToTemplates()
                }
            }

            Text(store.scenarioLibraryDirectoryPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                TextField(store.text("scenario_name"), text: $store.scenarioRenameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Button(store.text("rename_scenario")) {
                    store.renameSelectedScenario()
                }
                Button(store.text("import_scenario_file")) {
                    store.importScenarioFile()
                }
                Button(store.text("export_scenario_file")) {
                    store.exportSelectedScenarioFile()
                }
            }

            HStack(spacing: 8) {
                TextField(store.text("scenario_search"), text: $store.scenarioSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Picker(store.text("scenario_tag_filter"), selection: $store.selectedScenarioTag) {
                    Text(store.text("all_tags")).tag(String?.none)
                    ForEach(store.availableScenarioTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
                .frame(maxWidth: 260)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.text("scenario_tags"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(store.selectedScenario.sortedTagPairs, id: \.key) { pair in
                        HStack(spacing: 5) {
                            Text("\(pair.key)=\(pair.value)")
                            Button {
                                store.removeSelectedScenarioTag(pair.key)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    TextField(store.text("tag_key"), text: $store.scenarioTagKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    TextField(store.text("tag_value"), text: $store.scenarioTagValueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Button(store.text("add_tag")) {
                        store.addSelectedScenarioTag()
                    }
                }
            }

            if !store.recentScenarios.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.text("recent_scenarios"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(store.recentScenarios.prefix(5)) { scenario in
                            Button(scenario.name) {
                                store.selectSidebar(.scenario(scenario.id))
                            }
                        }
                    }
                }
            }

            if let status = store.scenarioLibraryStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = store.scenarioLibrarySaveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct ParameterizedTemplatePanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(store.text("parameterized_templates"), systemImage: "wand.and.stars")
                        .font(.headline)
                    Text(store.text("parameterized_templates_description"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.isGeneratingParameterizedTemplate ? store.text("generating") : store.text("generate_template_route")) {
                    Task { await store.generateParameterizedTemplate() }
                }
                .disabled(store.isGeneratingParameterizedTemplate)
            }

            Picker(store.text("template_type"), selection: $store.selectedTemplateKind) {
                ForEach(ParameterizedScenarioKind.allCases) { kind in
                    Text(kind.title(in: store)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(store.text("template_start")).font(.caption).foregroundStyle(.secondary)
                    TextField(store.text("latitude"), text: $store.templateStartLatitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField(store.text("longitude"), text: $store.templateStartLongitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    Button(store.text("use_current_picker")) {
                        store.useCurrentLocationAsTemplateStart()
                    }
                }

                GridRow {
                    Text(store.text("template_end")).font(.caption).foregroundStyle(.secondary)
                    TextField(store.text("latitude"), text: $store.templateEndLatitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField(store.text("longitude"), text: $store.templateEndLongitudeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    Button(store.text("use_current_picker")) {
                        store.useCurrentLocationAsTemplateEnd()
                    }
                }

                GridRow {
                    Text(store.text("template_timing")).font(.caption).foregroundStyle(.secondary)
                    TextField(store.text("template_speed_mps"), text: $store.templateSpeedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField(store.text("template_start_dwell"), text: $store.templateStartDwellText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField(store.text("template_end_dwell"), text: $store.templateEndDwellText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct NetworkDiagnosticsView: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.text("network"))
                            .font(.largeTitle.bold())
                        Text(store.text("network_description"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isRunningNetworkDiagnostics ? store.text("network_running") : store.text("run_network_diagnostics")) {
                        Task { await store.runNetworkDiagnostics() }
                    }
                    .disabled(store.isRunningNetworkDiagnostics)
                }

                NetworkVPNPanel(store: store)
                NetworkEndpointPanel(store: store)
                NetworkResultsPanel(store: store)
                StudioTelemetryPreviewPanel(store: store)
            }
            .padding(.top, 52)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NetworkVPNPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.text("vpn_nodes"), systemImage: "lock.shield")
                .font(.title3.bold())

            Picker(store.text("vpn_nodes"), selection: $store.selectedVPNNodeID) {
                ForEach(store.vpnNodes) { node in
                    Text("\(node.displayName) · \(node.regionCode)").tag(Optional(node.id))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)

            Toggle(store.text("kill_switch"), isOn: $store.killSwitchEnabled)
                .toggleStyle(.switch)

            Text(store.killSwitchEnabled ? store.text("kill_switch_enabled_note") : store.text("kill_switch_disabled_note"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(store.text("target_vpn_notice"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button(store.text("bind_vpn_to_scenario")) {
                    store.bindSelectedVPNNodeToScenario()
                }
                Button(store.text("export_json"), action: store.exportJSON)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
    }
}

struct NetworkEndpointPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.text("network_endpoints"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(store.text("latency_endpoint"))
                    TextField(store.text("latency_endpoint"), text: $store.networkLatencyEndpointText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 420)
                }
                GridRow {
                    Text(store.text("ip_endpoint"))
                    TextField(store.text("ip_endpoint"), text: $store.networkIPEndpointText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 420)
                }
                GridRow {
                    Text(store.text("dns_domains"))
                    TextField(store.text("dns_domains"), text: $store.networkDNSDomainsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 420)
                }
                GridRow {
                    Text(store.text("expected_country"))
                    TextField(store.text("expected_country"), text: $store.networkExpectedCountryText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
    }
}

struct NetworkResultsPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.text("network_results"), systemImage: "chart.bar.xaxis")
                .font(.title3.bold())

            if let status = store.networkDiagnosticsStatus {
                Text(status)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    resultCell(store.text("latency"), latencyText)
                    resultCell(store.text("public_ip"), ipText)
                    resultCell(store.text("dns_leak"), dnsText)
                }
                GridRow {
                    resultCell(store.text("status_code"), store.latencyResult?.statusCode.map(String.init) ?? "-")
                    resultCell(store.text("country"), store.ipGeolocationResult?.countryCode ?? "-")
                    resultCell(store.text("tested_domains"), store.dnsLeakResult?.testedDomains.joined(separator: ", ") ?? "-")
                }
            }

            if let raw = store.ipGeolocationResult?.raw, !raw.isEmpty {
                Text(raw.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
    }

    private var latencyText: String {
        guard let latency = store.latencyResult else {
            return "-"
        }
        return String(format: "%.0f ms", latency.milliseconds)
    }

    private var ipText: String {
        store.ipGeolocationResult?.ipAddress ?? "-"
    }

    private var dnsText: String {
        guard let dns = store.dnsLeakResult else {
            return "-"
        }
        return dns.leakDetected ? store.text("leak_detected") : store.text("no_leak_detected")
    }

    private func resultCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(minWidth: 180, alignment: .leading)
    }
}

struct StudioTelemetryPreviewPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        let scenarioPreview = store.telemetryPreview
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.text("telemetry_preview"), systemImage: "doc.text.magnifyingglass")
                    .font(.title3.bold())
                Spacer()
                Button(store.text("copy_fields")) {
                    store.copyTelemetryPreviewFields()
                }
                Button(store.text("copy_json")) {
                    store.copyTelemetryPreviewJSON()
                }
            }

            Text(store.text("telemetry_preview_description"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(scenarioPreview.payloadFields, id: \.0) { key, value in
                    GridRow {
                        Text(key)
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            previewJSONBlock(title: store.text("scenario_payload_json"), json: scenarioPreview.prettyPrintedJSONString)

            if let devicePreview = store.deviceTelemetryPreview {
                HStack {
                    Text(store.text("device_payload_json"))
                        .font(.headline)
                    Spacer()
                    Button(store.text("copy_device_json")) {
                        store.copyTelemetryPreviewJSON(deviceState: true)
                    }
                }
                previewJSONBlock(title: nil, json: devicePreview.prettyPrintedJSONString)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
    }

    private func previewJSONBlock(title: String?, json: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            TextEditor(text: .constant(json))
                .font(.system(.caption, design: .monospaced))
                .frame(height: 220)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
        }
    }
}

struct SettingsView: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.text("settings_title"))
                        .font(.largeTitle.bold())
                    Text(store.text("language_description"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.text("language"))
                                .font(.title3.bold())

                            Text(store.text("current_language"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker(store.text("current_language"), selection: $store.language) {
                                ForEach(StudioLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 620, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(store.text("about"))
                            .font(.title3.bold())
                    }

                    Text(store.text("about_body"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: 620, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: 1)
                )
            }
            .padding(.top, 52)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ScenarioMapPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.text("map"))
                    .font(.headline)
                Spacer()
                Picker(store.text("route_mode"), selection: Binding(
                    get: { store.routeMapMode },
                    set: { store.setRouteMapMode($0) }
                )) {
                    ForEach(RouteMapMode.allCases) { mode in
                        Text(mode.title(in: store)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Button(store.isPlanningRoute ? store.text("planning") : store.text("plan_route")) {
                    Task { await store.planRoute() }
                }
                .disabled(store.isPlanningRoute || store.selectedScenario.route.count < 2)
                Button(store.text("apply_planned_route")) {
                    store.applyPlannedRoute()
                }
                .disabled(store.plannedRoute.isEmpty)
                Button(store.text("swap_endpoints")) {
                    store.swapRouteEndpoints()
                }
                .disabled(store.selectedScenario.route.count < 2)
            }

            if store.isPlannedRouteStale && store.routeMapMode == .roadPlanning {
                Label(store.text("planned_route_stale"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            EditableRouteMapView(store: store)
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )

            RouteMetricsPanel(store: store)

            HStack(spacing: 14) {
                Label(store.text("map_hint_add"), systemImage: "mappin.and.ellipse")
                Label(store.text("map_hint_drag"), systemImage: "hand.draw")
                Label(store.text("map_hint_delete"), systemImage: "trash")
                Label(store.text("map_hint_blue"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(store.text("map_hint_green"), systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct RouteMetricsPanel: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        let metrics = store.selectedScenario.routeMetrics
        HStack(spacing: 12) {
            metric(store.text("total_distance"), distanceText(metrics.totalDistanceMeters))
            metric(store.text("total_duration"), timeText(metrics.totalDurationSeconds))
            metric(store.text("average_speed"), String(format: "%.2f m/s", metrics.averageSpeedMetersPerSecond))
            metric(store.text("points"), "\(metrics.pointCount)")
            metric(store.text("total_dwell"), timeText(metrics.totalDwellSeconds))
            metric(store.text("route_mode"), store.routeMapMode.title(in: store))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func timeText(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct EditableRouteMapView: NSViewRepresentable {
    @Bindable var store: ScenarioStudioStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapClick(_:)))
        click.buttonMask = 0x1
        mapView.addGestureRecognizer(click)
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.store = store
        context.coordinator.mapView = mapView
        context.coordinator.reload(mapView: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var store: ScenarioStudioStore
        weak var mapView: MKMapView?
        private var hasFitInitialRoute = false

        init(store: ScenarioStudioStore) {
            self.store = store
        }

        @objc func handleMapClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended, let mapView else {
                return
            }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            store.addPoint(at: coordinate)
        }

        func reload(mapView: MKMapView) {
            let selected = store.selectedPointID
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)

            let route = store.selectedScenario.route
            mapView.addAnnotations(route.enumerated().map { index, point in
                RoutePointAnnotation(point: point, index: index, selected: point.id == selected)
            })

            let routeCoordinates = route.map(\.coordinate)
            if routeCoordinates.count >= 2 {
                mapView.addOverlay(RoutePolyline(coordinates: routeCoordinates, count: routeCoordinates.count, kind: .route))
            }

            let plannedCoordinates = store.routeMapMode == .roadPlanning ? store.plannedRoute.map(\.coordinate) : []
            if plannedCoordinates.count >= 2 {
                mapView.addOverlay(RoutePolyline(coordinates: plannedCoordinates, count: plannedCoordinates.count, kind: .planned))
            }

            if !hasFitInitialRoute {
                fit(mapView: mapView, coordinates: plannedCoordinates.isEmpty ? routeCoordinates : plannedCoordinates)
                hasFitInitialRoute = true
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RoutePointAnnotation else {
                return nil
            }
            let identifier = "RoutePointAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView ??
                MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.isDraggable = true
            view.markerTintColor = annotation.selected ? .systemOrange : .systemRed
            view.glyphText = "\(annotation.index + 1)"
            let menu = NSMenu()
            let delete = NSMenuItem(title: store.text("remove"), action: #selector(deleteAnnotation(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = annotation.pointID
            menu.addItem(delete)
            view.menu = menu
            return view
        }

        @objc private func deleteAnnotation(_ sender: NSMenuItem) {
            guard let pointID = sender.representedObject as? String,
                  let point = store.selectedScenario.route.first(where: { $0.id == pointID }) else {
                return
            }
            store.removePoint(point)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? RoutePointAnnotation,
                  let point = store.selectedScenario.route.first(where: { $0.id == annotation.pointID }) else {
                return
            }
            store.selectPoint(point)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending || newState == .canceling,
                  let annotation = view.annotation as? RoutePointAnnotation else {
                return
            }
            store.updatePoint(annotation.pointID, coordinate: annotation.coordinate)
            view.dragState = .none
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? RoutePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            switch polyline.kind {
            case .route:
                renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.75)
                renderer.lineWidth = 3
            case .planned:
                renderer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.85)
                renderer.lineWidth = 5
                renderer.lineDashPattern = [8, 6]
            }
            return renderer
        }

        private func fit(mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            guard !coordinates.isEmpty else {
                return
            }
            let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
                let point = MKMapPoint(coordinate)
                return partial.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            mapView.setVisibleMapRect(
                rect,
                edgePadding: NSEdgeInsets(top: 42, left: 42, bottom: 42, right: 42),
                animated: true
            )
        }
    }
}

final class RoutePointAnnotation: NSObject, MKAnnotation {
    let pointID: String
    let index: Int
    let selected: Bool
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(point: RoutePoint, index: Int, selected: Bool) {
        self.pointID = point.id
        self.index = index
        self.selected = selected
        self.coordinate = point.coordinate
        self.title = point.label
    }
}

final class RoutePolyline: MKPolyline {
    enum Kind {
        case route
        case planned
    }

    var kind: Kind = .route

    convenience init(coordinates: [CLLocationCoordinate2D], count: Int, kind: Kind) {
        self.init(coordinates: coordinates, count: count)
        self.kind = kind
    }
}

struct RoutePointTable: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.text("route"))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(store.text("label")).bold()
                    Text(store.text("latitude")).bold()
                    Text(store.text("longitude")).bold()
                    Text(store.text("speed")).bold()
                    Text(store.text("elapsed")).bold()
                    Text(store.text("dwell")).bold()
                    Text("")
                }

                ForEach(store.selectedScenario.route) { point in
                    GridRow {
                        Button(point.label ?? "-") {
                            store.selectPoint(point)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(point.id == store.selectedPointID ? .orange : .primary)
                        Text(point.latitude, format: .number.precision(.fractionLength(4)))
                        Text(point.longitude, format: .number.precision(.fractionLength(4)))
                        Text(point.speed, format: .number.precision(.fractionLength(1)))
                        Text(point.elapsedSeconds, format: .number.precision(.fractionLength(0)))
                        Text(point.dwellSeconds, format: .number.precision(.fractionLength(0)))
                        Button(store.text("remove")) {
                            store.removePoint(point)
                        }
                    }
                }
            }
        }
    }
}

struct ExportPanel: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .frame(height: 180)
                .border(.separator)
        }
    }
}
