import Foundation

struct DeveloperDevice: Identifiable, Hashable {
    enum Kind: String {
        case physical
        case simulator
    }

    enum LocationCapability: Hashable {
        case simctl
        case dvtCoreDevice
        case ideviceSetLocation
        case unavailable(String)

        var isAvailable: Bool {
            switch self {
            case .simctl, .dvtCoreDevice, .ideviceSetLocation:
                true
            case .unavailable:
                false
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var platform: String
    var model: String
    var osVersion: String?
    var udid: String?
    var hostname: String?
    var pairingState: String?
    var tunnelState: String?
    var isAvailable: Bool
    var connectionSummary: String
    var locationCapability: LocationCapability
}

struct DeviceHealthCheck: Equatable {
    var deviceID: String
    var checkedAt: Date
    var items: [DeviceHealthItem]

    var hasBlockingFailure: Bool {
        items.contains { $0.status == .fail }
    }
}

struct DeviceHealthItem: Identifiable, Equatable {
    enum Status: String {
        case pass
        case warn
        case fail
        case unknown
    }

    var id: String
    var title: String
    var status: Status
    var detail: String
    var recommendation: String
}

struct DeveloperDeviceService {
    func listDevices() async throws -> [DeveloperDevice] {
        async let attachedUDIDsTask = listAttachedDeviceUDIDs()
        async let simulatorDevices = listSimulators()

        let attachedUDIDs = try await attachedUDIDsTask
        async let physicalDevices = listCoreDevices(attachedUDIDs: attachedUDIDs)
        return try await physicalDevices + simulatorDevices
    }

    func setLocation(device: DeveloperDevice, latitude: Double, longitude: Double) async throws {
        switch device.locationCapability {
        case .simctl:
            try await run(
                "/usr/bin/xcrun",
                arguments: ["simctl", "location", device.id, "set", "\(latitude),\(longitude)"]
            )
        case .dvtCoreDevice:
            try await setDVTLocation(device: device, latitude: latitude, longitude: longitude)
        case .ideviceSetLocation:
            guard let udid = device.udid else {
                throw DeveloperDeviceError.locationUnavailable("Device UDID is missing.")
            }
            try await run(
                "/opt/homebrew/bin/idevicesetlocation",
                arguments: ["-u", udid, "--", "\(latitude)", "\(longitude)"]
            )
        case let .unavailable(reason):
            throw DeveloperDeviceError.locationUnavailable(reason)
        }
    }

    func runHealthCheck(device: DeveloperDevice) async -> DeviceHealthCheck {
        var items: [DeviceHealthItem] = []

        items.append(
            DeviceHealthItem(
                id: "pairing",
                title: "Pairing and trust",
                status: device.pairingState == "paired" || device.kind == .simulator ? .pass : .fail,
                detail: device.kind == .simulator ? "Simulator does not require pairing." : "Pairing state: \(device.pairingState ?? "unknown").",
                recommendation: device.pairingState == "paired" || device.kind == .simulator ? "No action required." : "Unlock the iPhone, tap Trust, enable Developer Mode, then refresh devices."
            )
        )

        items.append(
            DeviceHealthItem(
                id: "connection",
                title: "Connection path",
                status: device.isAvailable ? .pass : .warn,
                detail: device.connectionSummary,
                recommendation: device.isAvailable ? "No action required." : "Reconnect USB/Wi-Fi, keep the device unlocked, then refresh the device list."
            )
        )

        switch device.kind {
        case .simulator:
            items.append(simulatorHealthItem(device: device))
        case .physical:
            items.append(contentsOf: await physicalHealthItems(device: device))
        }

        items.append(locationCapabilityHealthItem(device: device))

        return DeviceHealthCheck(deviceID: device.id, checkedAt: Date(), items: items)
    }

    func clearLocation(device: DeveloperDevice) async throws {
        switch device.locationCapability {
        case .simctl:
            try await run("/usr/bin/xcrun", arguments: ["simctl", "location", device.id, "clear"])
        case .dvtCoreDevice:
            try await clearDVTLocation(device: device)
        case .ideviceSetLocation:
            guard let udid = device.udid else {
                throw DeveloperDeviceError.locationUnavailable("Device UDID is missing.")
            }
            try await run("/opt/homebrew/bin/idevicesetlocation", arguments: ["-u", udid, "reset"])
        case let .unavailable(reason):
            throw DeveloperDeviceError.locationUnavailable(reason)
        }
    }

    private func listCoreDevices(attachedUDIDs: Set<String>) async throws -> [DeveloperDevice] {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coredevice-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--timeout", "5", "--json-output", outputURL.path]
        )

        let data = try Data(contentsOf: outputURL)
        let payload = try JSONDecoder().decode(CoreDeviceListPayload.self, from: data)
        return payload.result.devices.map { device in
            let pairingState = device.connectionProperties?.pairingState
            let tunnelState = device.connectionProperties?.tunnelState
            let hostname = device.connectionProperties?.potentialHostnames?.first
            let udid = device.hardwareProperties?.udid
            let isPaired = pairingState == "paired"
            let isAttached = udid.map { attachedUDIDs.contains($0) } ?? false
            let isAvailable = tunnelState != "unavailable" || isAttached
            let connectionSummary = connectionSummary(hostname: hostname, tunnelState: tunnelState, isAttached: isAttached)
            let locationCapability: DeveloperDevice.LocationCapability
            if supportsDVTLocation(osVersion: device.deviceProperties?.osVersionNumber), findPyMobileDevicePython() != nil {
                locationCapability = .dvtCoreDevice
            } else if !supportsDVTLocation(osVersion: device.deviceProperties?.osVersionNumber),
                      udid != nil,
                      isAttached,
                      FileManager.default.fileExists(atPath: "/opt/homebrew/bin/idevicesetlocation") {
                locationCapability = .ideviceSetLocation
            } else if supportsDVTLocation(osVersion: device.deviceProperties?.osVersionNumber) {
                locationCapability = .unavailable("iOS 17+ physical device location simulation requires pymobiledevice3. Install or keep the local .venv-pymobiledevice3/bin/python available, then refresh.")
            } else {
                locationCapability = .unavailable("Device is paired but not currently reachable by libimobiledevice. Connect USB/Wi-Fi, unlock the iPhone, tap Trust if prompted, then refresh.")
            }

            return DeveloperDevice(
                id: device.identifier,
                name: device.deviceProperties?.name ?? device.identifier,
                kind: .physical,
                platform: device.hardwareProperties?.platform ?? "iOS",
                model: device.hardwareProperties?.marketingName ?? device.hardwareProperties?.productType ?? "-",
                osVersion: device.deviceProperties?.osVersionNumber,
                udid: udid,
                hostname: hostname,
                pairingState: pairingState,
                tunnelState: tunnelState,
                isAvailable: isPaired && isAvailable,
                connectionSummary: connectionSummary,
                locationCapability: locationCapability
            )
        }
    }

    private func setDVTLocation(device: DeveloperDevice, latitude: Double, longitude: Double) async throws {
        try await runDVTLocationCommand(
            device: device,
            mode: "set",
            latitude: latitude,
            longitude: longitude
        )
    }

    private func clearDVTLocation(device: DeveloperDevice) async throws {
        try await runDVTLocationCommand(device: device, mode: "clear")
    }

    private func runDVTLocationCommand(
        device: DeveloperDevice,
        mode: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async throws {
        guard let udid = device.udid else {
            throw DeveloperDeviceError.locationUnavailable("Device UDID is missing.")
        }
        guard let python = findPyMobileDevicePython() else {
            throw DeveloperDeviceError.locationUnavailable("pymobiledevice3 Python runtime was not found. Expected .venv-pymobiledevice3/bin/python in this workspace.")
        }

        let keepAlive = try await startCoreDeviceTunnelKeepAlive(device: device)
        defer {
            if keepAlive.isRunning {
                keepAlive.terminate()
            }
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)
        let tunnelIP = try await currentTunnelIPAddress(device: device)
        let rsdPort = try await latestRSDPort(udid: udid)

        var arguments = ["-c", Self.dvtLocationPython, tunnelIP, "\(rsdPort)", mode]
        if let latitude, let longitude {
            arguments.append(contentsOf: ["\(latitude)", "\(longitude)"])
        }

        _ = try await runAndCapture(python, arguments: arguments, timeout: 20)
    }

    private func startCoreDeviceTunnelKeepAlive(device: DeveloperDevice) async throws -> Process {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "devicectl",
                "device",
                "notification",
                "observe",
                "--device",
                device.id,
                "--name",
                "com.enterprise.telemetryqa.keepalive",
                "--session-timeout",
                "45",
                "--timeout",
                "50"
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                continuation.resume(returning: process)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func currentTunnelIPAddress(device: DeveloperDevice) async throws -> String {
        let data = try await runAndCapture(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "info", "details", "--device", device.id],
            timeout: 12
        )
        let output = String(decoding: data, as: UTF8.self)
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.contains("tunnelIPAddress:") else {
                continue
            }
            let value = line
                .replacingOccurrences(of: "•", with: "")
                .split(separator: ":", maxSplits: 1)
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        throw DeveloperDeviceError.locationUnavailable("CoreDevice tunnel is not connected. Refresh the device list, keep the iPhone unlocked, and try again.")
    }

    private func latestRSDPort(udid: String) async throws -> Int {
        let predicate = "process == \"remotepairingd\" AND eventMessage CONTAINS[c] \"Creating RSD backend client device for server port\" AND eventMessage CONTAINS[c] \"\(udid)\""
        let data = try await runAndCapture(
            "/usr/bin/log",
            arguments: ["show", "--predicate", predicate, "--last", "1m", "--style", "compact"],
            timeout: 10
        )
        let output = String(decoding: data, as: UTF8.self)
        let pattern = #"server port ([0-9]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: output),
              let port = Int(output[range]) else {
            throw DeveloperDeviceError.locationUnavailable("Unable to find the CoreDevice RSD port in recent remotepairingd logs. Try again after refreshing the device.")
        }
        return port
    }

    private func listSimulators() async throws -> [DeveloperDevice] {
        let data = try await runAndCapture("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"])
        let payload = try JSONDecoder().decode(SimctlDeviceListPayload.self, from: data)

        return payload.devices.flatMap { runtime, devices in
            devices.map { device in
                DeveloperDevice(
                    id: device.udid,
                    name: device.name,
                    kind: .simulator,
                    platform: runtime,
                    model: device.deviceTypeIdentifier?.components(separatedBy: ".").last ?? "Simulator",
                    osVersion: nil,
                    udid: device.udid,
                    hostname: nil,
                    pairingState: nil,
                    tunnelState: device.state,
                    isAvailable: device.isAvailable,
                    connectionSummary: "Simulator: \(device.state)",
                    locationCapability: .simctl
                )
            }
        }
    }

    private func listAttachedDeviceUDIDs() async throws -> Set<String> {
        var udids = Set<String>()
        for arguments in [["-l"], ["-n", "-l"]] {
            guard let data = try? await runAndCapture("/opt/homebrew/bin/idevice_id", arguments: arguments) else {
                continue
            }
            let output = String(decoding: data, as: UTF8.self)
            for line in output.split(whereSeparator: \.isNewline) {
                if let udid = line.split(whereSeparator: \.isWhitespace).first, !udid.isEmpty {
                    udids.insert(String(udid))
                }
            }
        }
        return udids
    }

    private func simulatorHealthItem(device: DeveloperDevice) -> DeviceHealthItem {
        DeviceHealthItem(
            id: "simctl",
            title: "simctl location",
            status: device.isAvailable ? .pass : .fail,
            detail: "Simulator state: \(device.tunnelState ?? "unknown").",
            recommendation: device.isAvailable ? "simctl can set simulator location." : "Boot the simulator and refresh the device list."
        )
    }

    private func physicalHealthItems(device: DeveloperDevice) async -> [DeviceHealthItem] {
        var items: [DeviceHealthItem] = []
        let details = (try? await coreDeviceDetails(device: device)) ?? ""
        let lowercasedDetails = details.lowercased()

        let developerModeVisible = lowercasedDetails.contains("developermode") || lowercasedDetails.contains("developer mode")
        items.append(
            DeviceHealthItem(
                id: "developer-mode",
                title: "Developer Mode visibility",
                status: developerModeVisible ? .pass : .unknown,
                detail: developerModeVisible ? "Developer Mode details are visible through devicectl." : "devicectl did not expose a Developer Mode field.",
                recommendation: developerModeVisible ? "No action required." : "If location simulation fails, confirm Developer Mode is enabled on the iPhone."
            )
        )

        let ddiVisible = lowercasedDetails.contains("developer disk image") || lowercasedDetails.contains("ddi") || lowercasedDetails.contains("diskimage")
        items.append(
            DeviceHealthItem(
                id: "ddi",
                title: "Developer Disk Image",
                status: ddiVisible ? .pass : .unknown,
                detail: ddiVisible ? "Developer Disk Image details were found in devicectl output." : "No DDI field was found in devicectl output.",
                recommendation: ddiVisible ? "No action required." : "If DVT fails, open Xcode once or reconnect the device so CoreDevice can mount developer services."
            )
        )

        if supportsDVTLocation(osVersion: device.osVersion) {
            if let python = findPyMobileDevicePython() {
                items.append(
                    DeviceHealthItem(
                        id: "pymobiledevice3",
                        title: "pymobiledevice3 runtime",
                        status: .pass,
                        detail: python,
                        recommendation: "No action required."
                    )
                )
            } else {
                items.append(
                    DeviceHealthItem(
                        id: "pymobiledevice3",
                        title: "pymobiledevice3 runtime",
                        status: .fail,
                        detail: "No executable Python runtime with pymobiledevice3 support was found.",
                        recommendation: "Restore .venv-pymobiledevice3/bin/python or install pymobiledevice3, then refresh."
                    )
                )
            }

            let tunnelIP = try? await currentTunnelIPAddress(device: device)
            let rsdPort: Int?
            if let udid = device.udid {
                rsdPort = try? await latestRSDPort(udid: udid)
            } else {
                rsdPort = nil
            }
            items.append(
                DeviceHealthItem(
                    id: "coredevice-tunnel",
                    title: "CoreDevice tunnel",
                    status: tunnelIP == nil ? .fail : (rsdPort == nil ? .warn : .pass),
                    detail: "Tunnel IP: \(tunnelIP ?? "missing"), RSD port: \(rsdPort.map(String.init) ?? "missing").",
                    recommendation: tunnelIP == nil ? "Refresh devices, keep the iPhone unlocked, and retry." : (rsdPort == nil ? "Refresh the device list and retry location simulation to refresh remotepairingd logs." : "No action required.")
                )
            )
        } else {
            let hasIdeviceSetLocation = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/idevicesetlocation")
            items.append(
                DeviceHealthItem(
                    id: "idevicesetlocation",
                    title: "idevicesetlocation fallback",
                    status: hasIdeviceSetLocation ? .pass : .warn,
                    detail: hasIdeviceSetLocation ? "/opt/homebrew/bin/idevicesetlocation is available." : "idevicesetlocation is not installed.",
                    recommendation: hasIdeviceSetLocation ? "No action required." : "Install libimobiledevice tools if this older iOS device needs location simulation."
                )
            )
        }

        return items
    }

    private func locationCapabilityHealthItem(device: DeveloperDevice) -> DeviceHealthItem {
        switch device.locationCapability {
        case .simctl:
            return DeviceHealthItem(
                id: "location-capability",
                title: "Location simulation capability",
                status: .pass,
                detail: "Simulator location can be controlled with simctl.",
                recommendation: "No action required."
            )
        case .dvtCoreDevice:
            return DeviceHealthItem(
                id: "location-capability",
                title: "Location simulation capability",
                status: .pass,
                detail: "iOS 17+ CoreDevice DVT location simulation is available.",
                recommendation: "No action required."
            )
        case .ideviceSetLocation:
            return DeviceHealthItem(
                id: "location-capability",
                title: "Location simulation capability",
                status: .pass,
                detail: "libimobiledevice idevicesetlocation fallback is available.",
                recommendation: "No action required."
            )
        case let .unavailable(reason):
            return DeviceHealthItem(
                id: "location-capability",
                title: "Location simulation capability",
                status: .fail,
                detail: reason,
                recommendation: "Resolve the failed checks above, then refresh devices."
            )
        }
    }

    private func coreDeviceDetails(device: DeveloperDevice) async throws -> String {
        let data = try await runAndCapture(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "info", "details", "--device", device.id],
            timeout: 12
        )
        return String(decoding: data, as: UTF8.self)
    }

    private func connectionSummary(hostname: String?, tunnelState: String?, isAttached: Bool) -> String {
        if isAttached {
            return "Connected through libimobiledevice"
        }
        if let tunnelState, tunnelState != "unavailable" {
            return "CoreDevice tunnel: \(tunnelState)"
        }
        if let hostname, hostname.hasSuffix(".coredevice.local") {
            return "Trusted developer device, currently offline or not connected"
        }
        return "Trusted developer device"
    }

    @discardableResult
    private func supportsDVTLocation(osVersion: String?) -> Bool {
        guard let osVersion,
              let major = osVersion.split(separator: ".").first,
              let value = Int(major) else {
            return true
        }
        return value >= 17
    }

    private func findPyMobileDevicePython() -> String? {
        let searchRoots = upwardSearchRoots(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            + upwardSearchRoots(from: Bundle.main.bundleURL)
            + upwardSearchRoots(from: URL(fileURLWithPath: #filePath))
        let candidates = searchRoots.map { $0.appendingPathComponent(".venv-pymobiledevice3/bin/python").path }
            + ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func upwardSearchRoots(from url: URL) -> [URL] {
        var roots: [URL] = []
        var current = url
        for _ in 0..<8 {
            roots.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else {
                break
            }
            current = parent
        }
        return roots
    }

    @discardableResult
    private func run(_ executable: String, arguments: [String]) async throws -> Data {
        try await runAndCapture(executable, arguments: arguments, timeout: 20)
    }

    private func runAndCapture(_ executable: String, arguments: [String], timeout: TimeInterval = 30) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            let didTimeout = process.isRunning
            if didTimeout {
                process.terminate()
                process.waitUntilExit()
            } else {
                process.waitUntilExit()
            }

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            if didTimeout {
                throw DeveloperDeviceError.commandFailed("Command timed out after \(Int(timeout)) seconds: \(executable) \(arguments.joined(separator: " "))")
            }
            if process.terminationStatus == 0 {
                return output
            }
            let message = conciseErrorMessage(
                String(data: errorData, encoding: .utf8)
                    ?? String(data: output, encoding: .utf8)
                    ?? "Command failed."
            )
            throw DeveloperDeviceError.commandFailed(message)
        }.value
    }

    private func conciseErrorMessage(_ message: String) -> String {
        let lines = message
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let last = lines.last, last.contains("Connection reset by peer") {
            return "CoreDevice DVT connection closed after the device reset the peer connection. Retry once; if the map app already moved, the location was applied."
        }

        let tail = lines.suffix(8).joined(separator: "\n")
        return tail.isEmpty ? message : tail
    }

    private static let dvtLocationPython = """
import asyncio
import sys
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

async def main():
    host = sys.argv[1]
    port = int(sys.argv[2])
    mode = sys.argv[3]
    rsd = RemoteServiceDiscoveryService((host, port))
    await rsd.connect()
    try:
        async with DvtProvider(rsd) as dvt, LocationSimulation(dvt) as location_simulation:
            if mode == "set":
                await location_simulation.set(float(sys.argv[4]), float(sys.argv[5]))
            elif mode == "clear":
                await location_simulation.clear()
            else:
                raise ValueError(f"unsupported mode: {mode}")
    finally:
        try:
            await rsd.close()
        except Exception:
            pass

asyncio.run(main())
"""
}

enum DeveloperDeviceError: LocalizedError {
    case commandFailed(String)
    case locationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        case let .locationUnavailable(reason):
            reason
        }
    }
}

private struct CoreDeviceListPayload: Decodable {
    var result: Result

    struct Result: Decodable {
        var devices: [Device]
    }

    struct Device: Decodable {
        var identifier: String
        var connectionProperties: ConnectionProperties?
        var deviceProperties: DeviceProperties?
        var hardwareProperties: HardwareProperties?
    }

    struct ConnectionProperties: Decodable {
        var pairingState: String?
        var tunnelState: String?
        var potentialHostnames: [String]?
    }

    struct DeviceProperties: Decodable {
        var name: String?
        var osVersionNumber: String?
    }

    struct HardwareProperties: Decodable {
        var platform: String?
        var marketingName: String?
        var productType: String?
        var udid: String?
    }
}

private struct SimctlDeviceListPayload: Decodable {
    var devices: [String: [Device]]

    struct Device: Decodable {
        var name: String
        var udid: String
        var state: String
        var isAvailable: Bool
        var deviceTypeIdentifier: String?
    }
}
