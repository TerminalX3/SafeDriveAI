// Estimates speed along the direction of travel.
// The IMU is integrated at a high rate, and GPS corrects drift using the timestamp of the fix.
// SpeedMonitor feeds live samples.
// A short history lets a late GPS fix be matched to the motion time it belongs to.

import Foundation
import simd

/// Gravity-free along-track speed estimator. The IMU integrates at a high rate, and GPS corrects drift using the fix timestamp. `SpeedMonitor` and `ReplayMotionProvider` feed it samples.
struct SpeedFusion {
    private(set) var speedMps = 0.0
    private(set) var filteredAccel = 0.0
    private(set) var isStationary = true
    /// False until GPS has settled. The first fixes are often wildly wrong.
    private(set) var isDisplayReady = false
    private(set) var courseRadians: Double?
    private(set) var lastGpsSpeed = 0.0

    static let metersPerSecondSquaredPerG = 9.80665

    var usesNorthReference = true
    var hasLocation = false

    private var lastMotionTime: TimeInterval = 0
    private var lockoutUntil = Date.distantPast
    private var history: [Sample] = []
    private var pendingSpeed: Double?

    private let accelTau = 0.03
    private let gpsGain = 0.35

    mutating func reset() {
        speedMps = 0
        filteredAccel = 0
        isStationary = true
        courseRadians = nil
        lastGpsSpeed = 0
        lastMotionTime = 0
        lockoutUntil = .distantPast
        history.removeAll(keepingCapacity: true)
        pendingSpeed = nil
        hasLocation = false
        isDisplayReady = false
    }

    /// A startup glitch is a very high speed reported with a sloppy accuracy.
    static func isBelievableFix(doppler: Double, accuracy: Double) -> Bool {
        guard doppler >= 0, doppler < 70, accuracy.isFinite else { return false }
        if doppler > 40, accuracy > 2 { return false }
        if accuracy <= 5 { return true }
        return doppler <= 1.5
    }

    mutating func ingestGPS(
        doppler: Double,
        accuracy: Double,
        courseRadians: Double?,
        timestamp: Date,
        now: Date
    ) {
        guard Self.isBelievableFix(doppler: doppler, accuracy: accuracy) else { return }

        hasLocation = true
        if let courseRadians, courseRadians >= 0 {
            self.courseRadians = courseRadians
        }

        lastGpsSpeed = doppler
        var becameReady = false
        if !isDisplayReady {
            if let pendingSpeed, abs(pendingSpeed - doppler) <= 5.5 {
                isDisplayReady = true
                becameReady = true
            } else if doppler <= 1, accuracy <= 3 {
                isDisplayReady = true
                becameReady = true
            } else {
                self.pendingSpeed = doppler
            }
        }

        if becameReady {
            pendingSpeed = nil
            let disagreement = abs(speedMps - doppler) > 6
            let stopped = doppler <= max(0.4, accuracy)
            if disagreement || stopped {
                if stopped {
                    enterStationary()
                } else {
                    isStationary = false
                    speedMps = max(0, doppler)
                    filteredAccel = 0
                    lockoutUntil = now.addingTimeInterval(0.35)
                    history.removeAll(keepingCapacity: true)
                    record(speed: speedMps, now: now)
                }
                return
            }
        }

        let noise = max(0.4, accuracy)
        let gpsStopped = doppler <= noise
        let gpsMoving = doppler > noise + 0.3
        let launching = abs(filteredAccel) > 0.8

        if isStationary {
            if gpsMoving || launching {
                isStationary = false
                lockoutUntil = now.addingTimeInterval(0.35)
                if speedMps < doppler {
                    speedMps = doppler
                }
            } else if gpsStopped {
                speedMps = 0
            }
        } else if gpsStopped, abs(filteredAccel) < 0.35, now >= lockoutUntil {
            enterStationary()
        }

        if !isStationary {
            applyGpsCorrection(doppler, at: timestamp)
        }
    }

    mutating func ingestIMU(alongTrackAccel: Double, motionTimestamp: TimeInterval, now: Date) {
        let dt: TimeInterval
        if lastMotionTime == 0 {
            lastMotionTime = motionTimestamp
            dt = 0.01
        } else {
            dt = motionTimestamp - lastMotionTime
            lastMotionTime = motionTimestamp
        }
        guard dt > 0, dt < 0.05 else { return }

        let clamped = min(8, max(-12, alongTrackAccel))
        let alpha = dt / (accelTau + dt)
        filteredAccel += (clamped - filteredAccel) * alpha

        if isStationary {
            if abs(filteredAccel) > 0.75, hasLocation {
                isStationary = false
                lockoutUntil = now.addingTimeInterval(0.35)
            } else {
                speedMps = 0
                record(speed: 0, now: now)
                return
            }
        }

        speedMps = max(0, speedMps + filteredAccel * dt)
        record(speed: speedMps, now: now)

        if abs(filteredAccel) < 0.2, speedMps < 0.45, lastGpsSpeed < 0.7, now >= lockoutUntil {
            enterStationary()
        }
    }

    var speedMph: Double {
        speedMps * 2.2369362921
    }

    /// Core Motion `userAcceleration` is in g's. Fusion integrates m/s².
    static func metersPerSecondSquared(fromCoreMotionGs accel: SIMD3<Double>) -> SIMD3<Double> {
        accel * metersPerSecondSquaredPerG
    }

    mutating func ingestPhoneGPS(_ sample: GPSSample, now: Date) {
        guard let accuracy = sample.fusionAccuracy else { return }
        ingestGPS(
            doppler: sample.speedMps,
            accuracy: accuracy,
            courseRadians: sample.fusionCourseRadians,
            timestamp: sample.timestamp,
            now: now
        )
    }

    mutating func ingestPhoneIMU(
        coreMotionGs: SIMD3<Double>,
        rotation: simd_double3x3,
        motionTimestamp: TimeInterval,
        now: Date
    ) {
        let device = Self.metersPerSecondSquared(fromCoreMotionGs: coreMotionGs)
        let world = Self.worldUserAcceleration(deviceAccel: device, rotation: rotation)
        let along = Self.alongTrackAcceleration(
            worldAccel: world,
            courseRadians: courseRadians,
            usesNorthReference: usesNorthReference,
            filteredAccel: filteredAccel
        )
        ingestIMU(alongTrackAccel: along, motionTimestamp: motionTimestamp, now: now)
    }

    static func worldUserAcceleration(
        deviceAccel: SIMD3<Double>,
        rotation: simd_double3x3
    ) -> SIMD3<Double> {
        rotation * deviceAccel
    }

    /// GPS course is clockwise from north. World X = north, Y = east when using a
    /// Z-vertical Core Motion reference frame.
    static func alongTrackAcceleration(
        worldAccel: SIMD3<Double>,
        courseRadians: Double?,
        usesNorthReference: Bool,
        filteredAccel: Double
    ) -> Double {
        if usesNorthReference, let course = courseRadians {
            return worldAccel.x * cos(course) + worldAccel.y * sin(course)
        }
        // GPS course is often invalid until the car is already moving. Use the
        // full horizontal accel so an east/west launch is not dropped.
        let horizontal = hypot(worldAccel.x, worldAccel.y)
        if abs(filteredAccel) >= 0.15 {
            return copysign(horizontal, filteredAccel)
        }
        return horizontal
    }

    static func rotationMatrix(
        m11: Double, m12: Double, m13: Double,
        m21: Double, m22: Double, m23: Double,
        m31: Double, m32: Double, m33: Double
    ) -> simd_double3x3 {
        simd_double3x3(rows: [
            SIMD3(m11, m12, m13),
            SIMD3(m21, m22, m23),
            SIMD3(m31, m32, m33)
        ])
    }

    private mutating func applyGpsCorrection(_ doppler: Double, at timestamp: Date) {
        guard let historical = speed(at: timestamp) else {
            if speedMps < 0.4 {
                speedMps = max(0, doppler)
            }
            return
        }
        let delta = gpsGain * (doppler - historical)
        speedMps = max(0, speedMps + delta)
        for index in history.indices {
            history[index].speed = max(0, history[index].speed + delta)
        }
    }

    private mutating func enterStationary() {
        isStationary = true
        speedMps = 0
        filteredAccel = 0
        history.removeAll(keepingCapacity: true)
    }

    private mutating func record(speed: Double, now: Date) {
        history.append(Sample(time: now, speed: speed))
        if history.count > 400 {
            history.removeFirst(history.count - 400)
        }
    }

    private func speed(at time: Date) -> Double? {
        guard let first = history.first, let last = history.last else { return nil }
        if time <= first.time { return first.speed }
        if time >= last.time { return last.speed }
        for index in 1..<history.count {
            let next = history[index]
            if next.time >= time {
                let previous = history[index - 1]
                let span = next.time.timeIntervalSince(previous.time)
                guard span > 0 else { return next.speed }
                let blend = time.timeIntervalSince(previous.time) / span
                return previous.speed + (next.speed - previous.speed) * blend
            }
        }
        return last.speed
    }

    /// One fused speed kept so a later GPS fix can be matched to the motion time it belongs to.
    private struct Sample {
        let time: Date
        var speed: Double
    }
}
