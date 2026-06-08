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
    var selectedDeveloperDeviceID: String?
    var developerDeviceStatus: String?
    var isRefreshingDeveloperDevices = false
    var locationLatitudeText = "31.2304"
    var locationLongitudeText = "121.4737"
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
    private let developerDeviceService = DeveloperDeviceService()
    private let xcodeDebugSessionService = XcodeDebugSessionService()

    var selectedScenario: TelemetryScenario {
        get {
            scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
        }
        set {
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
            developerDeviceStatus = text("developer_devices_location_set")
        } catch {
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

            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(.orange)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text("\(result.coordinate.latitude, format: .number.precision(.fractionLength(4))), \(result.coordinate.longitude, format: .number.precision(.fractionLength(4)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if result.id != searchResults.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            }

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
        } catch {
            searchError = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    private func selectSearchResult(_ result: LocationSearchResult) {
        store.updateManualDeviceLocation(result.coordinate)
        searchText = result.title
        searchResults = []
        position = .region(
            MKCoordinateRegion(
                center: result.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
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
