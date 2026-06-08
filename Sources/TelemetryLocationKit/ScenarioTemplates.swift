import Foundation

public enum ScenarioTemplates {
    public static let all: [TelemetryScenario] = [
        deliveryRoute,
        cityNavigation,
        fitnessRun,
        crossCity,
        tunnelDropout,
        indoorDrift
    ]

    public static let deliveryRoute = TelemetryScenario(
        name: "Delivery Route",
        description: "Short urban pickup and drop-off flow.",
        route: [
            RoutePoint(latitude: 31.2304, longitude: 121.4737, speed: 0, elapsedSeconds: 0, dwellSeconds: 30, label: "Pickup"),
            RoutePoint(latitude: 31.2312, longitude: 121.4770, speed: 6, elapsedSeconds: 120, label: "Block A"),
            RoutePoint(latitude: 31.2330, longitude: 121.4802, speed: 5, elapsedSeconds: 240, dwellSeconds: 45, label: "Drop-off")
        ],
        expectedTelemetryTags: ["template": "delivery", "is_simulated": "true"]
    )

    public static let cityNavigation = TelemetryScenario(
        name: "City Navigation",
        description: "Steady navigation across dense urban roads.",
        route: [
            RoutePoint(latitude: 39.9042, longitude: 116.4074, speed: 0, elapsedSeconds: 0, label: "Start"),
            RoutePoint(latitude: 39.9142, longitude: 116.4174, speed: 12, elapsedSeconds: 180),
            RoutePoint(latitude: 39.9242, longitude: 116.4274, speed: 14, elapsedSeconds: 360, label: "End")
        ],
        expectedTelemetryTags: ["template": "navigation", "is_simulated": "true"]
    )

    public static let fitnessRun = TelemetryScenario(
        name: "Fitness Run",
        description: "Low-speed route for sports telemetry.",
        route: [
            RoutePoint(latitude: 22.5431, longitude: 114.0579, speed: 2.8, elapsedSeconds: 0),
            RoutePoint(latitude: 22.5450, longitude: 114.0600, speed: 3.2, elapsedSeconds: 180),
            RoutePoint(latitude: 22.5470, longitude: 114.0615, speed: 3.0, elapsedSeconds: 360)
        ],
        expectedTelemetryTags: ["template": "fitness", "is_simulated": "true"]
    )

    public static let crossCity = TelemetryScenario(
        name: "Cross City",
        description: "Longer route with faster movement.",
        route: [
            RoutePoint(latitude: 30.5728, longitude: 104.0668, speed: 0, elapsedSeconds: 0, dwellSeconds: 60),
            RoutePoint(latitude: 30.6500, longitude: 104.0900, speed: 20, elapsedSeconds: 600),
            RoutePoint(latitude: 30.7350, longitude: 104.1200, speed: 18, elapsedSeconds: 1200)
        ],
        expectedTelemetryTags: ["template": "cross_city", "is_simulated": "true"]
    )

    public static let tunnelDropout = TelemetryScenario(
        name: "Tunnel Dropout",
        description: "Route with low accuracy segment for tunnel-like behavior.",
        route: [
            RoutePoint(latitude: 23.1291, longitude: 113.2644, horizontalAccuracy: 8, speed: 10, elapsedSeconds: 0),
            RoutePoint(latitude: 23.1350, longitude: 113.2700, horizontalAccuracy: 80, speed: 8, elapsedSeconds: 180),
            RoutePoint(latitude: 23.1410, longitude: 113.2760, horizontalAccuracy: 10, speed: 12, elapsedSeconds: 360)
        ],
        expectedTelemetryTags: ["template": "tunnel", "is_simulated": "true"]
    )

    public static let indoorDrift = TelemetryScenario(
        name: "Indoor Drift",
        description: "Small coordinate changes with low speed and lower accuracy.",
        route: [
            RoutePoint(latitude: 30.2741, longitude: 120.1551, horizontalAccuracy: 35, speed: 0.4, elapsedSeconds: 0, dwellSeconds: 20),
            RoutePoint(latitude: 30.2742, longitude: 120.1554, horizontalAccuracy: 45, speed: 0.6, elapsedSeconds: 90),
            RoutePoint(latitude: 30.2740, longitude: 120.1552, horizontalAccuracy: 40, speed: 0.3, elapsedSeconds: 180)
        ],
        expectedTelemetryTags: ["template": "indoor_drift", "is_simulated": "true"]
    )
}
