import CoreLocation
import Foundation

@MainActor
public final class CoreLocationProvider: NSObject, LocationProvider, @preconcurrency CLLocationManagerDelegate {
    public nonisolated var descriptor: LocationProviderDescriptor {
        LocationProviderDescriptor(kind: .coreLocation, source: "core_location")
    }

    private let manager: CLLocationManager
    private var continuation: AsyncThrowingStream<CLLocation, Error>.Continuation?

    public init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public nonisolated func locations() -> AsyncThrowingStream<CLLocation, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                self.continuation = continuation
                self.manager.requestWhenInUseAuthorization()
                self.manager.startUpdatingLocation()
            }

            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.manager.stopUpdatingLocation()
                    self.continuation = nil
                }
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            continuation?.yield(location)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}
