import MapKit
import AppKit
import SwiftUI
import TelemetryLocationKit

@main
struct TelemetryScenarioStudioApp: App {
    @State private var store = ScenarioStudioStore()

    var body: some Scene {
        WindowGroup {
            ScenarioStudioView(store: store)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
@Observable
final class ScenarioStudioStore {
    var scenarios: [TelemetryScenario] = ScenarioTemplates.all
    var selectedScenarioID: String?
    var selectedModule: StudioModule = .scenarios
    var sidebarSelection: StudioSidebarSelection?
    var developerDevices: [DeveloperDevice] = []
    var selectedDeveloperDeviceID: String? {
        didSet {
            if oldValue != selectedDeveloperDeviceID {
                stopRoutePlayback(resetToIdle: true)
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
    var isPlanningRoute = false
    var exportedGPX: String = ""
    var exportedJSON: String = ""
    var importText: String = ""
    var errorMessage: String?
    var language: StudioLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
        }
    }

    private static let languageDefaultsKey = "TelemetryScenarioStudio.language"
    private static let recentLocationsDefaultsKey = "TelemetryScenarioStudio.recentLocations"
    private static let favoriteLocationsDefaultsKey = "TelemetryScenarioStudio.favoriteLocations"
    @ObservationIgnored private var routePlaybackTask: Task<Void, Never>?
    private let developerDeviceService = DeveloperDeviceService()
    private let xcodeDebugSessionService = XcodeDebugSessionService()

    var selectedScenario: TelemetryScenario {
        get {
            scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
        }
        set {
            if selectedScenarioID != nil, selectedScenarioID != newValue.id {
                stopRoutePlayback(resetToIdle: true)
            }
            if let index = scenarios.firstIndex(where: { $0.id == newValue.id }) {
                scenarios[index] = newValue
            }
            selectedScenarioID = newValue.id
            sidebarSelection = .scenario(newValue.id)
        }
    }

    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: Self.languageDefaultsKey)
        self.language = savedLanguage.flatMap(StudioLanguage.init(rawValue:)) ?? .english
        let defaultWorkspacePath = xcodeDebugSessionService.defaultWorkspacePath()
        self.xcodeWorkspacePath = defaultWorkspacePath
        self.xcodeWorkspaceName = URL(fileURLWithPath: defaultWorkspacePath).lastPathComponent
        self.xcodeSchemeName = "TelemetryQAConsole"
        selectedScenarioID = scenarios.first?.id
        sidebarSelection = scenarios.first.map { .scenario($0.id) }
        selectedPointID = scenarios.first?.route.first?.id
        recentLocations = Self.loadLocations(forKey: Self.recentLocationsDefaultsKey)
        favoriteLocations = Self.loadLocations(forKey: Self.favoriteLocationsDefaultsKey)
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
        plannedRoute = []
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
        plannedRoute = []
    }

    func removePoint(_ point: RoutePoint) {
        var scenario = selectedScenario
        scenario.route.removeAll { $0.id == point.id }
        selectedScenario = scenario
        selectedPointID = scenario.route.first?.id
        plannedRoute = []
    }

    func selectPoint(_ point: RoutePoint) {
        selectedPointID = point.id
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
        errorMessage = nil
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
            plannedRoute = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSidebar(_ selection: StudioSidebarSelection?) {
        sidebarSelection = selection
        switch selection {
        case let .scenario(id):
            selectedModule = .scenarios
            selectedScenarioID = id
            selectedPointID = selectedScenario.route.first?.id
            plannedRoute = []
        case .developerDevices:
            selectedModule = .developerDevices
        case .settings:
            selectedModule = .settings
        case nil:
            break
        }
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

    var xcodeDebugSummary: String {
        let device = selectedDevice?.name ?? text("automatic")
        return String(format: text("xcode_auto_summary"), device, selectedScenario.name)
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
        routePlaybackTask = Task { [weak self] in
            await self?.runRoutePlayback(device: selectedDevice, scenario: scenario, speed: speed, loops: shouldLoop)
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
        loops: Bool
    ) async {
        repeat {
            for index in scenario.route.indices {
                if Task.isCancelled {
                    return
                }

                while routePlaybackState == .paused, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if Task.isCancelled {
                    return
                }

                if index > 0 {
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
    case settings
}

enum StudioModule: String, CaseIterable, Identifiable {
    case scenarios
    case developerDevices
    case settings

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .scenarios:
            "map"
        case .developerDevices:
            "iphone.gen3"
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
        case .settings:
            store.text("settings")
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
        "planning": "Planning...",
        "plan_route": "Plan Route",
        "apply_planned_route": "Apply Planned Route",
        "map_hint_add": "Click map to add a route point",
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
        "planning": "规划中...",
        "plan_route": "规划路线",
        "apply_planned_route": "应用规划路线",
        "map_hint_add": "点击地图添加路线点",
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

enum ScenarioStudioError: LocalizedError {
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .noRouteFound:
            "MapKit did not return a route for the selected points."
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
            DeveloperDevicesView(store: store)
        case .settings:
            SettingsView(store: store)
        default:
            ScenarioEditorView(store: store)
        }
    }
}

struct EmbeddedStudioSidebar: View {
    @Bindable var store: ScenarioStudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            sidebarSection(store.text("scenarios"))

            ForEach(store.scenarios) { scenario in
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
                                store.selectedDeveloperDeviceID = device.id
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
            }

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

                ScenarioMapPanel(store: store)
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
    @State private var position: MapCameraPosition = .automatic

    private var scenarioRouteCoordinates: [CLLocationCoordinate2D] {
        store.selectedScenario.route.map(\.coordinate)
    }

    private var plannedRouteCoordinates: [CLLocationCoordinate2D] {
        store.plannedRoute.map(\.coordinate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.text("map"))
                    .font(.headline)
                Spacer()
                Button(store.text("fit_route")) {
                    fitRoute()
                }
                Button(store.isPlanningRoute ? store.text("planning") : store.text("plan_route")) {
                    Task {
                        await store.planRoute()
                        fitPlannedRoute()
                    }
                }
                .disabled(store.isPlanningRoute || store.selectedScenario.route.count < 2)
                Button(store.text("apply_planned_route")) {
                    store.applyPlannedRoute()
                    fitRoute()
                }
                .disabled(store.plannedRoute.isEmpty)
            }

            MapReader { proxy in
                Map(position: $position) {
                    if scenarioRouteCoordinates.count >= 2 {
                        MapPolyline(coordinates: scenarioRouteCoordinates)
                            .stroke(.blue, lineWidth: 3)
                    }

                    if plannedRouteCoordinates.count >= 2 {
                        MapPolyline(coordinates: plannedRouteCoordinates)
                            .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                    }

                    ForEach(store.selectedScenario.route) { point in
                        Annotation(point.label ?? store.text("point"), coordinate: point.coordinate) {
                            Button {
                                store.selectPoint(point)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(point.id == store.selectedPointID ? .orange : .red)
                                        .frame(width: 18, height: 18)
                                    Circle()
                                        .stroke(.white, lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        store.addPoint(at: coordinate)
                    }
                }
                .onAppear(perform: fitRoute)
                .onChange(of: store.selectedScenarioID) { _, _ in
                    store.selectedPointID = store.selectedScenario.route.first?.id
                    store.plannedRoute = []
                    fitRoute()
                }
            }

            HStack(spacing: 14) {
                Label(store.text("map_hint_add"), systemImage: "mappin.and.ellipse")
                Label(store.text("map_hint_blue"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(store.text("map_hint_green"), systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func fitRoute() {
        let coordinates = scenarioRouteCoordinates
        guard !coordinates.isEmpty else {
            position = .automatic
            return
        }
        position = .region(region(for: coordinates))
    }

    private func fitPlannedRoute() {
        let coordinates = plannedRouteCoordinates.isEmpty ? scenarioRouteCoordinates : plannedRouteCoordinates
        guard !coordinates.isEmpty else {
            position = .automatic
            return
        }
        position = .region(region(for: coordinates))
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let minLatitude = coordinates.map(\.latitude).min() ?? 31.2304
        let maxLatitude = coordinates.map(\.latitude).max() ?? 31.2304
        let minLongitude = coordinates.map(\.longitude).min() ?? 121.4737
        let maxLongitude = coordinates.map(\.longitude).max() ?? 121.4737
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 0.01),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
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
