import CoreLocation
import Foundation

public enum LocationProviderKind: String, Codable, Sendable {
    case coreLocation
    case simulatedRoute
}

public struct LocationProviderDescriptor: Codable, Equatable, Sendable {
    public var kind: LocationProviderKind
    public var scenarioID: String?
    public var source: String

    public init(kind: LocationProviderKind, scenarioID: String? = nil, source: String) {
        self.kind = kind
        self.scenarioID = scenarioID
        self.source = source
    }
}

public protocol LocationProvider: Sendable {
    var descriptor: LocationProviderDescriptor { get }
    func locations() -> AsyncThrowingStream<CLLocation, Error>
}

public struct TelemetryEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var scenarioID: String?
    public var source: String
    public var isSimulated: Bool
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var speed: Double
    public var course: Double
    public var vpnNodeID: String?
    public var ipCountryCode: String?
    public var dnsLeakDetected: Bool?
    public var tags: [String: String]

    public init(
        timestamp: Date = Date(),
        scenarioID: String?,
        source: String,
        isSimulated: Bool,
        location: CLLocation,
        vpnNodeID: String? = nil,
        ipCountryCode: String? = nil,
        dnsLeakDetected: Bool? = nil,
        tags: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.scenarioID = scenarioID
        self.source = source
        self.isSimulated = isSimulated
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.speed = location.speed
        self.course = location.course
        self.vpnNodeID = vpnNodeID
        self.ipCountryCode = ipCountryCode
        self.dnsLeakDetected = dnsLeakDetected
        self.tags = tags
    }
}

public struct TelemetryEventPreview: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var scenarioID: String?
    public var source: String
    public var isSimulated: Bool
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var horizontalAccuracy: Double?
    public var verticalAccuracy: Double?
    public var speed: Double?
    public var course: Double?
    public var scenarioName: String?
    public var routePointIndex: Int?
    public var routeElapsedSeconds: TimeInterval?
    public var vpnNodeID: String?
    public var vpnNodeName: String?
    public var vpnRegionCode: String?
    public var publicIPAddress: String?
    public var ipCountryCode: String?
    public var dnsLeakDetected: Bool?
    public var tags: [String: String]

    public init(
        timestamp: Date = Date(),
        scenarioID: String?,
        source: String = "qa_sdk",
        isSimulated: Bool = true,
        latitude: Double?,
        longitude: Double?,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        scenarioName: String? = nil,
        routePointIndex: Int? = nil,
        routeElapsedSeconds: TimeInterval? = nil,
        vpnNodeID: String? = nil,
        vpnNodeName: String? = nil,
        vpnRegionCode: String? = nil,
        publicIPAddress: String? = nil,
        ipCountryCode: String? = nil,
        dnsLeakDetected: Bool? = nil,
        tags: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.scenarioID = scenarioID
        self.source = source
        self.isSimulated = isSimulated
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.scenarioName = scenarioName
        self.routePointIndex = routePointIndex
        self.routeElapsedSeconds = routeElapsedSeconds
        self.vpnNodeID = vpnNodeID
        self.vpnNodeName = vpnNodeName
        self.vpnRegionCode = vpnRegionCode
        self.publicIPAddress = publicIPAddress
        self.ipCountryCode = ipCountryCode
        self.dnsLeakDetected = dnsLeakDetected
        self.tags = tags
    }

    public init(
        event: TelemetryEvent,
        vpnNode: VPNNode? = nil,
        publicIPAddress: String? = nil
    ) {
        self.init(
            timestamp: event.timestamp,
            scenarioID: event.scenarioID,
            source: event.source,
            isSimulated: event.isSimulated,
            latitude: event.latitude,
            longitude: event.longitude,
            altitude: event.altitude,
            speed: event.speed,
            course: event.course,
            vpnNodeID: event.vpnNodeID ?? vpnNode?.id,
            vpnNodeName: vpnNode?.displayName,
            vpnRegionCode: vpnNode?.regionCode,
            publicIPAddress: publicIPAddress,
            ipCountryCode: event.ipCountryCode,
            dnsLeakDetected: event.dnsLeakDetected,
            tags: event.tags
        )
    }

    public static func scenarioPreview(
        scenario: TelemetryScenario,
        location: CLLocation? = nil,
        routePoint: RoutePoint? = nil,
        routePointIndex: Int? = nil,
        routeElapsedSeconds: TimeInterval? = nil,
        ipResult: IPGeolocationResult? = nil,
        dnsResult: DNSLeakResult? = nil,
        source: String = "qa_sdk"
    ) -> TelemetryEventPreview {
        let point = routePoint ?? scenario.route.first
        let networkProfile = scenario.networkProfile
        let vpnNode = networkProfile?.vpnNode
        return TelemetryEventPreview(
            scenarioID: scenario.id,
            source: source,
            isSimulated: true,
            latitude: location?.coordinate.latitude ?? point?.latitude,
            longitude: location?.coordinate.longitude ?? point?.longitude,
            altitude: location?.altitude ?? point?.altitude,
            horizontalAccuracy: location?.horizontalAccuracy ?? point?.horizontalAccuracy,
            verticalAccuracy: location?.verticalAccuracy ?? point?.verticalAccuracy,
            speed: location?.speed ?? point?.speed,
            course: location?.course ?? point?.course,
            scenarioName: scenario.name,
            routePointIndex: routePointIndex,
            routeElapsedSeconds: routeElapsedSeconds ?? point?.elapsedSeconds,
            vpnNodeID: vpnNode?.id,
            vpnNodeName: vpnNode?.displayName,
            vpnRegionCode: vpnNode?.regionCode ?? networkProfile?.regionCode,
            publicIPAddress: ipResult?.ipAddress,
            ipCountryCode: ipResult?.countryCode ?? networkProfile?.expectedCountryCode,
            dnsLeakDetected: dnsResult?.leakDetected,
            tags: scenario.expectedTelemetryTags
        )
    }

    public var payloadFields: [(String, String)] {
        var values: [(String, String)] = [
            ("timestamp", ISO8601DateFormatter().string(from: timestamp)),
            ("is_simulated", isSimulated ? "true" : "false"),
            ("source", source)
        ]
        if let scenarioID {
            values.append(("scenario_id", scenarioID))
        }
        if let latitude {
            values.append(("latitude", String(format: "%.6f", latitude)))
        }
        if let longitude {
            values.append(("longitude", String(format: "%.6f", longitude)))
        }
        if let altitude {
            values.append(("altitude", String(format: "%.2f", altitude)))
        }
        if let horizontalAccuracy {
            values.append(("horizontal_accuracy", String(format: "%.2f", horizontalAccuracy)))
        }
        if let verticalAccuracy {
            values.append(("vertical_accuracy", String(format: "%.2f", verticalAccuracy)))
        }
        if let speed {
            values.append(("speed", String(format: "%.2f", speed)))
        }
        if let course {
            values.append(("course", String(format: "%.1f", course)))
        }
        if let scenarioName {
            values.append(("scenario_name", scenarioName))
        }
        if let routePointIndex {
            values.append(("route_point_index", "\(routePointIndex)"))
        }
        if let routeElapsedSeconds {
            values.append(("route_elapsed_seconds", String(format: "%.0f", routeElapsedSeconds)))
        }
        if let vpnNodeID {
            values.append(("vpn_node_id", vpnNodeID))
        }
        if let vpnNodeName {
            values.append(("vpn_node_name", vpnNodeName))
        }
        if let vpnRegionCode {
            values.append(("vpn_region", vpnRegionCode))
        }
        if let publicIPAddress {
            values.append(("public_ip", publicIPAddress))
        }
        if let ipCountryCode {
            values.append(("ip_country", ipCountryCode))
        }
        if let dnsLeakDetected {
            values.append(("dns_leak_detected", dnsLeakDetected ? "true" : "false"))
        }
        for key in tags.keys.sorted() {
            values.append(("tag.\(key)", tags[key] ?? ""))
        }
        return values
    }

    public var payload: TelemetryEventPreviewPayload {
        TelemetryEventPreviewPayload(
            timestamp: timestamp,
            isSimulated: isSimulated,
            source: source,
            scenarioID: scenarioID,
            scenarioName: scenarioName,
            routePointIndex: routePointIndex,
            routeElapsedSeconds: routeElapsedSeconds,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed,
            course: course,
            vpnNodeID: vpnNodeID,
            vpnNodeName: vpnNodeName,
            vpnRegionCode: vpnRegionCode,
            publicIPAddress: publicIPAddress,
            ipCountryCode: ipCountryCode,
            dnsLeakDetected: dnsLeakDetected,
            tags: tags
        )
    }

    public var prettyPrintedJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct TelemetryEventPreviewPayload: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var isSimulated: Bool
    public var source: String
    public var scenarioID: String?
    public var scenarioName: String?
    public var routePointIndex: Int?
    public var routeElapsedSeconds: TimeInterval?
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var horizontalAccuracy: Double?
    public var verticalAccuracy: Double?
    public var speed: Double?
    public var course: Double?
    public var vpnNodeID: String?
    public var vpnNodeName: String?
    public var vpnRegionCode: String?
    public var publicIPAddress: String?
    public var ipCountryCode: String?
    public var dnsLeakDetected: Bool?
    public var tags: [String: String]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case isSimulated = "is_simulated"
        case source
        case scenarioID = "scenario_id"
        case scenarioName = "scenario_name"
        case routePointIndex = "route_point_index"
        case routeElapsedSeconds = "route_elapsed_seconds"
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy = "horizontal_accuracy"
        case verticalAccuracy = "vertical_accuracy"
        case speed
        case course
        case vpnNodeID = "vpn_node_id"
        case vpnNodeName = "vpn_node_name"
        case vpnRegionCode = "vpn_region"
        case publicIPAddress = "public_ip"
        case ipCountryCode = "ip_country"
        case dnsLeakDetected = "dns_leak_detected"
        case tags
    }
}

public protocol TelemetryEventSink: Sendable {
    func record(_ event: TelemetryEvent) async throws
}

public actor InMemoryTelemetryEventSink: TelemetryEventSink {
    private var storage: [TelemetryEvent] = []

    public init() {}

    public func record(_ event: TelemetryEvent) async throws {
        storage.append(event)
    }

    public func events() -> [TelemetryEvent] {
        storage
    }
}
