// Plays a recorded drive back in time order so speed fusion can run without a car.
// It implements the same motion and location callbacks the live providers use.
// SpeedFusion receives the samples the way it would on the road.

import Foundation
import simd

/// Desk playback of a recorded drive. It feeds IMU and GPS samples in time order so `SpeedFusion` can run without a car.
final class ReplayMotionProvider: MotionDataProvider, LocationDataProvider {
    var onIMU: ((IMUSample) -> Void)?
    var onGPS: ((GPSSample) -> Void)?
    var onAuthorizationChange: (() -> Void)?
    var authorizationDenied = false
    var locationMessage: String? = "Replaying recorded drive."

    private let samples: [DriveLogSample]
    private var timer: DispatchSourceTimer?
    private var index = 0
    private let queue = DispatchQueue(label: "ReplayMotionProvider")
    private let realtime: Bool

    init(samples: [DriveLogSample], realtime: Bool = false) {
        self.samples = samples.sorted { $0.t < $1.t }
        self.realtime = realtime
    }

    convenience init(resource name: String, bundle: Bundle = .main, realtime: Bool = false) {
        self.init(samples: DriveSensorLog.loadFromBundle(named: name, bundle: bundle), realtime: realtime)
    }

    func start() {
        stop()
        index = 0
        guard !samples.isEmpty else { return }

        if realtime {
            playRealtime()
        } else {
            playImmediately()
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Synchronous playback for unit tests — no wall-clock delay.
    func playImmediately() {
        for sample in samples {
            emit(sample)
        }
    }

    func replayInto(_ fusion: inout SpeedFusion, usesNorthReference: Bool = true) {
        fusion.reset()
        fusion.usesNorthReference = usesNorthReference
        let epoch = Date(timeIntervalSince1970: 1_000_000)
        for sample in samples {
            let now = epoch.addingTimeInterval(sample.t)
            if sample.kind == "gps", let speed = sample.v {
                fusion.ingestGPS(
                    doppler: speed,
                    accuracy: sample.acc ?? 0.3,
                    courseRadians: (sample.course ?? -1) >= 0 ? (sample.course ?? 0) * .pi / 180 : nil,
                    timestamp: sample.gpsT.map { Date(timeIntervalSince1970: $0) } ?? now,
                    now: now
                )
            } else if sample.kind == "imu", let accel = sample.deviceAccel {
                let rotation = sample.rotation ?? matrix_identity_double3x3
                let world = SpeedFusion.worldUserAcceleration(deviceAccel: accel, rotation: rotation)
                let along = SpeedFusion.alongTrackAcceleration(
                    worldAccel: world,
                    courseRadians: fusion.courseRadians,
                    usesNorthReference: usesNorthReference,
                    filteredAccel: fusion.filteredAccel
                )
                fusion.ingestIMU(
                    alongTrackAccel: along,
                    motionTimestamp: sample.motionT ?? sample.t,
                    now: now
                )
            }
        }
    }

    private func playRealtime() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.01)
        let start = samples.first?.t ?? 0
        let wallStart = Date()
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(wallStart) + start
            while self.index < self.samples.count, self.samples[self.index].t <= elapsed {
                let sample = self.samples[self.index]
                self.index += 1
                DispatchQueue.main.async {
                    self.emit(sample)
                }
            }
            if self.index >= self.samples.count {
                self.stop()
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func emit(_ sample: DriveLogSample) {
        if sample.kind == "gps", let speed = sample.v {
            onGPS?(
                GPSSample(
                    timestamp: sample.gpsT.map { Date(timeIntervalSince1970: $0) } ?? Date(),
                    latitude: sample.lat ?? 0,
                    longitude: sample.lon ?? 0,
                    speedMps: speed,
                    speedAccuracy: sample.acc ?? 0.3,
                    courseDegrees: sample.course ?? -1,
                    courseAccuracy: 5,
                    horizontalAccuracy: 5
                )
            )
        } else if sample.kind == "imu", let accel = sample.deviceAccel, let rotation = sample.rotation {
            onIMU?(
                IMUSample(
                    motionTimestamp: sample.motionT ?? sample.t,
                    deviceAccel: accel,
                    rotation: rotation
                )
            )
        }
    }
}
