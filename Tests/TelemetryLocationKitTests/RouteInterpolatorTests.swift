import CoreLocation
import Testing
@testable import TelemetryLocationKit

@Test
func staticLocationReturnsOnlyPoint() throws {
    let scenario = TelemetryScenario(
        name: "Static",
        route: [
            RoutePoint(latitude: 31.2, longitude: 121.4, altitude: 12, speed: 0, elapsedSeconds: 0)
        ]
    )

    let interpolator = try RouteInterpolator(scenario: scenario)
    let location = interpolator.location(at: 120)

    #expect(location.coordinate.latitude == 31.2)
    #expect(location.coordinate.longitude == 121.4)
    #expect(location.altitude == 12)
}

@Test
func routeInterpolatesBetweenPoints() throws {
    let scenario = TelemetryScenario(
        name: "Route",
        route: [
            RoutePoint(latitude: 0, longitude: 0, speed: 0, elapsedSeconds: 0),
            RoutePoint(latitude: 10, longitude: 20, speed: 5, elapsedSeconds: 100)
        ]
    )

    let interpolator = try RouteInterpolator(scenario: scenario)
    let location = interpolator.location(at: 50)

    #expect(location.coordinate.latitude == 5)
    #expect(location.coordinate.longitude == 10)
    #expect(location.speed == 5)
}

@Test
func dwellPointHoldsPosition() throws {
    let scenario = TelemetryScenario(
        name: "Dwell",
        route: [
            RoutePoint(latitude: 1, longitude: 2, speed: 0, elapsedSeconds: 0, dwellSeconds: 30),
            RoutePoint(latitude: 3, longitude: 4, speed: 5, elapsedSeconds: 90)
        ]
    )

    let interpolator = try RouteInterpolator(scenario: scenario)
    let location = interpolator.location(at: 20)

    #expect(location.coordinate.latitude == 1)
    #expect(location.coordinate.longitude == 2)
}

@Test
func invalidScenarioThrowsForEmptyRoute() throws {
    let scenario = TelemetryScenario(name: "Empty", route: [])

    #expect(throws: TelemetryScenarioError.emptyRoute) {
        try RouteInterpolator(scenario: scenario)
    }
}

@Test
func invalidCoordinateThrows() throws {
    let scenario = TelemetryScenario(
        name: "Invalid",
        route: [
            RoutePoint(latitude: 120, longitude: 121, elapsedSeconds: 0)
        ]
    )

    #expect(throws: TelemetryScenarioError.invalidCoordinate(latitude: 120, longitude: 121)) {
        try scenario.validate()
    }
}
