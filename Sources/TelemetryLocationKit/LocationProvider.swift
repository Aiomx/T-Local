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
    public var speed: Double?
    public var course: Double?
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
        speed: Double? = nil,
        course: Double? = nil,
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
        self.speed = speed
        self.course = course
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
            speed: location?.speed ?? point?.speed,
            course: location?.course ?? point?.course,
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
        if let speed {
            values.append(("speed", String(format: "%.2f", speed)))
        }
        if let course {
            values.append(("course", String(format: "%.1f", course)))
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
