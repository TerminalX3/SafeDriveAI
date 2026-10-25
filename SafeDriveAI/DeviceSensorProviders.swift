// Reads the phone's motion and location while a drive is running.
// DeviceMotionProvider delivers acceleration and attitude at about 100 Hz.
// DeviceLocationProvider delivers GPS speed, course, and coordinates, and reports when location access is denied.
// SpeedMonitor owns both providers.

import CoreLocation
import CoreMotion
import Foundation
import simd

/// Live Core Motion source for `SpeedMonitor`. It delivers `IMUSample` values at about 100 Hz.
final class DeviceMotionProvider: MotionDataProvider {
    var onIMU: ((IMUSample) -> Void)?
    private(set) var usesNorthReference = false

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "DeviceMotionProvider"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.01

        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        if available.contains(.xTrueNorthZVertical) {
            frame = .xTrueNorthZVertical
            usesNorthReference = true
        } else if available.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical
            usesNorthReference = true
        } else {
            frame = .xArbitraryZVertical
            usesNorthReference = false
        }

        motionManager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.attitude.rotationMatrix
            self.onIMU?(
                IMUSample(
                    motionTimestamp: motion.timestamp,
                    deviceAccel: SpeedFusion.metersPerSecondSquared(
                        fromCoreMotionGs: SIMD3(acceleration.x, acceleration.y, acceleration.z)
                    ),
                    rotation: SpeedFusion.rotationMatrix(
                        m11: rotation.m11, m12: rotation.m12, m13: rotation.m13,
                        m21: rotation.m21, m22: rotation.m22, m23: rotation.m23,
                        m31: rotation.m31, m32: rotation.m32, m33: rotation.m33
                    )
                )
            )
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

/// Live Core Location source for `SpeedMonitor`. It delivers `GPSSample` values and reports when location access is denied.
final class DeviceLocationProvider: NSObject, LocationDataProvider, CLLocationManagerDelegate {
    var onGPS: ((GPSSample) -> Void)?
    var onAuthorizationChange: (() -> Void)?
    private(set) var authorizationDenied = false
    private(set) var locationMessage: String?

    private let locationManager = CLLocationManager()

    func start() {
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                locationMessage = "Turn on Precise Location in Settings for an accurate speedometer."
            }
            locationManager.startUpdatingLocation()
        default:
            authorizationDenied = true
            locationMessage = "Enable Location to show speed and speed limits."
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            locationMessage = nil
            if manager.accuracyAuthorization == .reducedAccuracy {
                locationMessage = "Turn on Precise Location in Settings for an accurate speedometer."
            }
            manager.startUpdatingLocation()
        case .notDetermined:
            break
        default:
            authorizationDenied = true
            locationMessage = "Enable Location to show speed and speed limits."
            manager.stopUpdatingLocation()
        }
        onAuthorizationChange?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onGPS?(
            GPSSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                speedMps: location.speed,
                speedAccuracy: location.speedAccuracy,
                courseDegrees: location.course,
                courseAccuracy: location.courseAccuracy,
                horizontalAccuracy: location.horizontalAccuracy
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationMessage = error.localizedDescription
    }
}
