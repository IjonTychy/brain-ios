import CoreLocation
import BrainCore

// Bridge between Action Primitives and CoreLocation.
// Provides location.current for skills that need the user's location.
@MainActor
final class LocationBridge: NSObject, CLLocationManagerDelegate {
    // @MainActor: CLLocationManager must be used from main thread.
    // Mutable state (continuation, isRequestInFlight) is protected by actor isolation.
    let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var isRequestInFlight = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // Request current location (one-shot).
    // Guards against concurrent calls — only one location request at a time.
    func currentLocation() async -> LocationInfo? {
        // Prevent concurrent requests (race condition on continuation)
        guard !isRequestInFlight else { return nil }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for authorization
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        isRequestInFlight = true
        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.locationContinuation = continuation
            self.manager.requestLocation()
        }
        isRequestInFlight = false

        guard let location else { return nil }
        return LocationInfo(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude
        )
    }

    // CLLocationManagerDelegate — callbacks may arrive on non-main thread
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

struct LocationInfo: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double

    var expressionValue: ExpressionValue {
        .object([
            "latitude": .double(latitude),
            "longitude": .double(longitude),
            "altitude": .double(altitude),
        ])
    }
}

// MARK: - Action Handler

@MainActor
final class LocationCurrentHandler: ActionHandler {
    let type = "location.current"
    private let bridge = LocationBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let location = await bridge.currentLocation() else {
            return .error("Standort nicht verfügbar")
        }
        return .value(location.expressionValue)
    }
}

@MainActor
final class LocationGeofenceHandler: ActionHandler {
    let type = "location.geofence"
    // Persistent bridge instance so CLLocationManager stays alive for geofencing
    private let bridge = LocationBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let latitude = properties["latitude"]?.doubleValue,
              let longitude = properties["longitude"]?.doubleValue else {
            return .error("location.geofence: latitude und longitude erforderlich")
        }
        let radius = properties["radius"]?.doubleValue ?? 100.0
        let identifier = properties["identifier"]?.stringValue ?? UUID().uuidString

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return .error("location.geofence: Geofencing nicht verfügbar")
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: min(radius, bridge.manager.maximumRegionMonitoringDistance),
            identifier: identifier
        )
        region.notifyOnEntry = properties["onEntry"]?.boolValue ?? true
        region.notifyOnExit = properties["onExit"]?.boolValue ?? false

        bridge.manager.startMonitoring(for: region)
        return .value(.object([
            "identifier": .string(identifier),
            "latitude": .double(latitude),
            "longitude": .double(longitude),
            "radius": .double(region.radius),
            "status": .string("monitoring"),
        ]))
    }
}
