import CoreLocation
import Foundation

public struct TelemetryScenario: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var route: [RoutePoint]
    public var networkProfile: NetworkProfile?
    public var expectedTelemetryTags: [String: String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        route: [RoutePoint],
        networkProfile: NetworkProfile? = nil,
        expectedTelemetryTags: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.route = route
        self.networkProfile = networkProfile
        self.expectedTelemetryTags = expectedTelemetryTags
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TelemetryScenarioError.emptyName
        }
        guard !route.isEmpty else {
            throw TelemetryScenarioError.emptyRoute
        }

        var previousElapsed: TimeInterval = -1
        for point in route {
            try point.validate()
            guard point.elapsedSeconds >= previousElapsed else {
                throw TelemetryScenarioError.nonMonotonicRoute
            }
            previousElapsed = point.elapsedSeconds
        }
    }

    public var duration: TimeInterval {
        route.last?.elapsedSeconds ?? 0
    }
}

public struct RoutePoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var speed: Double
    public var course: Double
    public var elapsedSeconds: TimeInterval
    public var dwellSeconds: TimeInterval
    public var label: String?

    public init(
        id: String = UUID().uuidString,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 5,
        speed: Double = 0,
        course: Double = -1,
        elapsedSeconds: TimeInterval,
        dwellSeconds: TimeInterval = 0,
        label: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.elapsedSeconds = elapsedSeconds
        self.dwellSeconds = dwellSeconds
        self.label = label
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public func validate() throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw TelemetryScenarioError.invalidCoordinate(latitude: latitude, longitude: longitude)
        }
        guard elapsedSeconds >= 0 else {
            throw TelemetryScenarioError.invalidElapsedSeconds(elapsedSeconds)
        }
        guard dwellSeconds >= 0 else {
            throw TelemetryScenarioError.invalidDwellSeconds(dwellSeconds)
        }
        guard horizontalAccuracy >= 0, verticalAccuracy >= 0 else {
            throw TelemetryScenarioError.invalidAccuracy
        }
        guard speed >= 0 else {
            throw TelemetryScenarioError.invalidSpeed(speed)
        }
    }
}

public struct NetworkProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var regionCode: String
    public var vpnNode: VPNNode?
    public var expectedCountryCode: String?
    public var dnsTestDomains: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        regionCode: String,
        vpnNode: VPNNode? = nil,
        expectedCountryCode: String? = nil,
        dnsTestDomains: [String] = ["example.com", "apple.com"]
    ) {
        self.id = id
        self.name = name
        self.regionCode = regionCode
        self.vpnNode = vpnNode
        self.expectedCountryCode = expectedCountryCode
        self.dnsTestDomains = dnsTestDomains
    }
}

public struct VPNNode: Codable, Equatable, Identifiable, Sendable {
    public enum Authentication: Codable, Equatable, Sendable {
        case usernamePassword(username: String, passwordReference: String)
        case certificate(identityReference: String)
    }

    public var id: String
    public var displayName: String
    public var regionCode: String
    public var serverHost: String
    public var remoteIdentifier: String
    public var localIdentifier: String?
    public var authentication: Authentication
    public var dnsServers: [String]
    public var healthCheckURL: URL?

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        regionCode: String,
        serverHost: String,
        remoteIdentifier: String,
        localIdentifier: String? = nil,
        authentication: Authentication,
        dnsServers: [String] = [],
        healthCheckURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.regionCode = regionCode
        self.serverHost = serverHost
        self.remoteIdentifier = remoteIdentifier
        self.localIdentifier = localIdentifier
        self.authentication = authentication
        self.dnsServers = dnsServers
        self.healthCheckURL = healthCheckURL
    }
}

public enum TelemetryScenarioError: Error, Equatable, LocalizedError {
    case emptyName
    case emptyRoute
    case nonMonotonicRoute
    case invalidCoordinate(latitude: Double, longitude: Double)
    case invalidElapsedSeconds(TimeInterval)
    case invalidDwellSeconds(TimeInterval)
    case invalidAccuracy
    case invalidSpeed(Double)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            "Scenario name cannot be empty."
        case .emptyRoute:
            "Scenario route must contain at least one point."
        case .nonMonotonicRoute:
            "Route points must be ordered by elapsedSeconds."
        case let .invalidCoordinate(latitude, longitude):
            "Invalid coordinate: \(latitude), \(longitude)."
        case let .invalidElapsedSeconds(value):
            "elapsedSeconds must be non-negative: \(value)."
        case let .invalidDwellSeconds(value):
            "dwellSeconds must be non-negative: \(value)."
        case .invalidAccuracy:
            "Location accuracy values must be non-negative."
        case let .invalidSpeed(value):
            "Speed must be non-negative: \(value)."
        }
    }
}
