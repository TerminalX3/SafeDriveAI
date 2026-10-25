// Defines the IMU and GPS samples that speed fusion consumes, and the protocols for supplying them.
// DeviceMotionProvider and DeviceLocationProvider are the live phone sources.
// ReplayMotionProvider implements the same protocols from a saved log.

import CoreLocation
import Foundation
import simd

/// One device-motion sample: user acceleration in meters per second squared and the attitude rotation. `SpeedFusion` integrates these between GPS fixes.
struct IMUSample {
    var motionTimestamp: TimeInterval
    var deviceAccel: SIMD3<Double>
    var rotation: simd_double3x3
}

/// One location fix, including speed and course. `SpeedFusion` uses it to correct IMU drift, and `SpeedMonitor` uses the coordinate for the speed-limit lookup.
struct GPSSample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speedMps: Double
    var speedAccuracy: Double
    var courseDegrees: Double
    var courseAccuracy: Double
    var horizontalAccuracy: Double

    /// iOS uses -1 for "unknown", not "discard this speed".
    var fusionAccuracy: Double? {
        guard speedMps >= 0 else { return nil }
        return speedAccuracy >= 0 ? speedAccuracy : 1.5
    }

    var fusionCourseRadians: Double? {
        guard courseAccuracy >= 0, courseDegrees >= 0 else { return nil }
        return courseDegrees * .pi / 180
    }
}

protocol MotionDataProvider: AnyObject {
    var onIMU: ((IMUSample) -> Void)? { get set }
    func start()
    func stop()
}

protocol LocationDataProvider: AnyObject {
    var onGPS: ((GPSSample) -> Void)? { get set }
    var onAuthorizationChange: (() -> Void)? { get set }
    var authorizationDenied: Bool { get }
    var locationMessage: String? { get }
    func start()
    func stop()
}
