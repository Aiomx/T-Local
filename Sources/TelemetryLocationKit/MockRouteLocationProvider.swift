import CoreLocation
import Foundation

public struct MockRouteLocationProvider: LocationProvider {
    public var descriptor: LocationProviderDescriptor
    public var scenario: TelemetryScenario
    public var playbackSpeed: Double
    public var updateInterval: TimeInterval

    public init(
        scenario: TelemetryScenario,
        playbackSpeed: Double = 1,
        updateInterval: TimeInterval = 1
    ) {
        self.descriptor = LocationProviderDescriptor(
            kind: .simulatedRoute,
            scenarioID: scenario.id,
            source: "qa_sdk"
        )
        self.scenario = scenario
        self.playbackSpeed = max(playbackSpeed, 0.01)
        self.updateInterval = max(updateInterval, 0.1)
    }

    public func locations() -> AsyncThrowingStream<CLLocation, Error> {
        AsyncThrowingStream { continuation in
            let scenario = scenario
            let playbackSpeed = playbackSpeed
            let updateInterval = updateInterval

            let task = Task {
                do {
                    let interpolator = try RouteInterpolator(scenario: scenario)
                    var elapsed: TimeInterval = 0

                    while !Task.isCancelled, elapsed <= scenario.duration {
                        continuation.yield(interpolator.location(at: elapsed))
                        try await Task.sleep(for: .seconds(updateInterval))
                        elapsed += updateInterval * playbackSpeed
                    }

                    if !Task.isCancelled, scenario.duration > 0 {
                        continuation.yield(interpolator.location(at: scenario.duration))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
