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
