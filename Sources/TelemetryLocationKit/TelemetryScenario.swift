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

    public var routeMetrics: RouteMetrics {
        RouteMetrics(route: route)
    }

    public var sortedTagPairs: [(key: String, value: String)] {
        expectedTelemetryTags
            .map { (key: $0.key, value: $0.value) }
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
    }

    public func matchesSearchText(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        let haystack = [
            name,
            description,
            expectedTelemetryTags.map { "\($0.key) \($0.value)" }.joined(separator: " "),
            route.compactMap(\.label).joined(separator: " ")
        ].joined(separator: " ")

        return haystack.localizedCaseInsensitiveContains(query)
    }

    public func hasTag(_ tag: String?) -> Bool {
        guard let tag, !tag.isEmpty else {
            return true
        }
        return expectedTelemetryTags.keys.contains(tag)
    }

    public func reversedRoutePreservingTiming() -> TelemetryScenario {
        guard route.count > 1 else {
            return self
        }

        let original = route
        let reversed = Array(original.reversed())
        let originalIntervals = original.indices.dropFirst().map { index in
            max(0, original[index].elapsedSeconds - original[index - 1].elapsedSeconds)
        }.reversed()

        var elapsed: TimeInterval = 0
        var intervalIterator = originalIntervals.makeIterator()
        let points = reversed.enumerated().map { index, point in
            if index > 0 {
                elapsed += intervalIterator.next() ?? 0
            }

            var label = point.label
            if index == 0 {
                label = original.first?.label ?? point.label
            } else if index == reversed.count - 1 {
                label = original.last?.label ?? point.label
            }

            return RoutePoint(
                id: point.id,
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
                speed: point.speed,
                course: point.course,
                elapsedSeconds: elapsed,
                dwellSeconds: point.dwellSeconds,
                label: label
            )
        }

        return TelemetryScenario(
            id: id,
            name: name,
            description: description,
            route: points,
            networkProfile: networkProfile,
            expectedTelemetryTags: expectedTelemetryTags
        )
    }
}

public struct RouteMetrics: Codable, Equatable, Sendable {
    public var pointCount: Int
    public var totalDistanceMeters: Double
    public var totalDurationSeconds: TimeInterval
    public var totalDwellSeconds: TimeInterval
    public var averageSpeedMetersPerSecond: Double

    public init(route: [RoutePoint]) {
        pointCount = route.count
        totalDistanceMeters = zip(route, route.dropFirst()).reduce(0) { partial, pair in
            partial + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        totalDwellSeconds = route.reduce(0) { $0 + $1.dwellSeconds }
        totalDurationSeconds = (route.last?.elapsedSeconds ?? 0) + (route.last?.dwellSeconds ?? 0)
        averageSpeedMetersPerSecond = totalDurationSeconds > 0 ? totalDistanceMeters / totalDurationSeconds : 0
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
