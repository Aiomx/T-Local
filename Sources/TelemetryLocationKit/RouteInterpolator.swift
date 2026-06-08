import CoreLocation
import Foundation

public struct RouteInterpolator: Sendable {
    public var scenario: TelemetryScenario

    public init(scenario: TelemetryScenario) throws {
        try scenario.validate()
        self.scenario = scenario
    }

    public func location(at elapsedSeconds: TimeInterval, timestamp: Date = Date()) -> CLLocation {
        let route = scenario.route
        guard route.count > 1 else {
            return location(from: route[0], timestamp: timestamp)
        }

        let boundedElapsed = min(max(0, elapsedSeconds), scenario.duration)

        for point in route where boundedElapsed >= point.elapsedSeconds && boundedElapsed <= point.elapsedSeconds + point.dwellSeconds {
            return location(from: point, timestamp: timestamp)
        }

        if boundedElapsed <= route[0].elapsedSeconds {
            return location(from: route[0], timestamp: timestamp)
        }

        for index in 0..<(route.count - 1) {
            let start = route[index]
            let end = route[index + 1]
            let startDeparture = start.elapsedSeconds + start.dwellSeconds

            if boundedElapsed <= startDeparture {
                return location(from: start, timestamp: timestamp)
            }

            guard boundedElapsed >= startDeparture, boundedElapsed <= end.elapsedSeconds else {
                continue
            }

            let segmentDuration = max(end.elapsedSeconds - startDeparture, 0.001)
            let progress = (boundedElapsed - startDeparture) / segmentDuration
            return interpolatedLocation(from: start, to: end, progress: progress, timestamp: timestamp)
        }

        return location(from: route[route.count - 1], timestamp: timestamp)
    }

    private func interpolatedLocation(from start: RoutePoint, to end: RoutePoint, progress: Double, timestamp: Date) -> CLLocation {
        let clampedProgress = min(max(progress, 0), 1)
        let latitude = start.latitude + (end.latitude - start.latitude) * clampedProgress
        let longitude = start.longitude + (end.longitude - start.longitude) * clampedProgress
        let altitude = start.altitude + (end.altitude - start.altitude) * clampedProgress
        let horizontalAccuracy = start.horizontalAccuracy + (end.horizontalAccuracy - start.horizontalAccuracy) * clampedProgress
        let verticalAccuracy = start.verticalAccuracy + (end.verticalAccuracy - start.verticalAccuracy) * clampedProgress
        let course = start.course >= 0 ? start.course : bearing(from: start.coordinate, to: end.coordinate)
        let speed = end.speed > 0 ? end.speed : metersPerSecond(from: start, to: end)

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }

    private func location(from point: RoutePoint, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: point.coordinate,
            altitude: point.altitude,
            horizontalAccuracy: point.horizontalAccuracy,
            verticalAccuracy: point.verticalAccuracy,
            course: point.course,
            speed: point.speed,
            timestamp: timestamp
        )
    }

    private func metersPerSecond(from start: RoutePoint, to end: RoutePoint) -> Double {
        let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        let duration = max(end.elapsedSeconds - start.elapsedSeconds - start.dwellSeconds, 0.001)
        return distance / duration
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
