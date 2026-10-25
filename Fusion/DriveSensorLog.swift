// Records and reloads the IMU and GPS samples from a drive as JSON lines.
// DriveSensorLogger appends live samples while SpeedMonitor is running.
// ReplayMotionProvider reads the file so speed fusion can be replayed at a desk.

import Foundation
import simd

/// One IMU or GPS row in a drive log. `DriveSensorLogger` writes these as JSON lines, and `ReplayMotionProvider` plays them back.
struct DriveLogSample: Codable, Equatable {
    var t: TimeInterval
    var kind: String
    var ax: Double?
    var ay: Double?
    var az: Double?
    var m11: Double?
    var m12: Double?
    var m13: Double?
    var m21: Double?
    var m22: Double?
    var m23: Double?
    var m31: Double?
    var m32: Double?
    var m33: Double?
    var motionT: TimeInterval?
    var v: Double?
    var acc: Double?
    var course: Double?
    var lat: Double?
    var lon: Double?
    var gpsT: TimeInterval?

    static func imu(
        t: TimeInterval,
        accel: SIMD3<Double>,
        rotation: simd_double3x3,
        motionTimestamp: TimeInterval
    ) -> DriveLogSample {
        DriveLogSample(
            t: t,
            kind: "imu",
            ax: accel.x,
            ay: accel.y,
            az: accel.z,
            m11: rotation[0, 0],
            m12: rotation[1, 0],
            m13: rotation[2, 0],
            m21: rotation[0, 1],
            m22: rotation[1, 1],
            m23: rotation[2, 1],
            m31: rotation[0, 2],
            m32: rotation[1, 2],
            m33: rotation[2, 2],
            motionT: motionTimestamp,
            v: nil,
            acc: nil,
            course: nil,
            lat: nil,
            lon: nil,
            gpsT: nil
        )
    }

    static func gps(_ sample: GPSSample, t: TimeInterval) -> DriveLogSample {
        DriveLogSample(
            t: t,
            kind: "gps",
            ax: nil,
            ay: nil,
            az: nil,
            m11: nil,
            m12: nil,
            m13: nil,
            m21: nil,
            m22: nil,
            m23: nil,
            m31: nil,
            m32: nil,
            m33: nil,
            motionT: nil,
            v: sample.speedMps,
            acc: sample.speedAccuracy,
            course: sample.courseDegrees,
            lat: sample.latitude,
            lon: sample.longitude,
            gpsT: sample.timestamp.timeIntervalSince1970
        )
    }

    var deviceAccel: SIMD3<Double>? {
        guard let ax, let ay, let az else { return nil }
        return SIMD3(ax, ay, az)
    }

    var rotation: simd_double3x3? {
        guard
            let m11, let m12, let m13,
            let m21, let m22, let m23,
            let m31, let m32, let m33
        else { return nil }
        return SpeedFusion.rotationMatrix(
            m11: m11, m12: m12, m13: m13,
            m21: m21, m22: m22, m23: m23,
            m31: m31, m32: m32, m33: m33
        )
    }
}

/// Finds and reads the latest drive's JSON-line sensor log from Documents or the app bundle.
enum DriveSensorLog {
    static let fileName = "latest-drive.jsonl"

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func load(from url: URL) throws -> [DriveLogSample] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let data = Data(line.utf8)
            return try? decoder.decode(DriveLogSample.self, from: data)
        }
    }

    static func loadFromBundle(named name: String, bundle: Bundle = .main) -> [DriveLogSample] {
        guard let url = bundle.url(forResource: name, withExtension: "jsonl")
            ?? bundle.url(forResource: name, withExtension: "json")
        else { return [] }
        return (try? load(from: url)) ?? []
    }
}

/// Appends live IMU and GPS samples to `DriveSensorLog`'s file while a drive is running. `SpeedMonitor` owns one.
final class DriveSensorLogger {
    private let queue = DispatchQueue(label: "DriveSensorLogger")
    private var handle: FileHandle?
    private var sessionStart = Date()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    var isRunning: Bool { handle != nil }

    func start() {
        queue.sync {
            stopLocked()
            let url = DriveSensorLog.fileURL
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            sessionStart = Date()
        }
    }

    func stop() {
        queue.sync { stopLocked() }
    }

    func logIMU(accel: SIMD3<Double>, rotation: simd_double3x3, motionTimestamp: TimeInterval) {
        append(
            DriveLogSample.imu(
                t: Date().timeIntervalSince(sessionStart),
                accel: accel,
                rotation: rotation,
                motionTimestamp: motionTimestamp
            )
        )
    }

    func logGPS(_ sample: GPSSample) {
        append(DriveLogSample.gps(sample, t: Date().timeIntervalSince(sessionStart)))
    }

    private func append(_ sample: DriveLogSample) {
        queue.async { [weak self] in
            guard let self, let handle = self.handle,
                  var data = try? self.encoder.encode(sample)
            else { return }
            data.append(0x0A)
            try? handle.write(contentsOf: data)
        }
    }

    private func stopLocked() {
        try? handle?.close()
        handle = nil
    }
}
