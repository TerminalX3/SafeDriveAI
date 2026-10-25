// Writes fused speed at the IMU rate into a local CSV so it can be plotted later.
// SpeedMonitor starts and stops the file.
// Each row is one motion sample after fusion, with GPS speed and location beside it.

import Foundation

/// Writes fused speed at IMU rate to a local CSV for later plotting. `SpeedMonitor` starts and stops the recording.
final class SpeedCSVRecorder {
    private let queue = DispatchQueue(label: "SpeedCSVRecorder")
    private let directory: URL
    private var handle: FileHandle?
    private var sessionStart = Date()
    private(set) var fileURL: URL?

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeedTraces", isDirectory: true)
    }

    init(directory: URL = SpeedCSVRecorder.documentsDirectory) {
        self.directory = directory
    }

    var isRecording: Bool {
        queue.sync { handle != nil }
    }

    @discardableResult
    func start(at date: Date = Date()) -> URL? {
        queue.sync {
            stopLocked()
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("speed-\(Self.fileStamp.string(from: date)).csv")
            let header = "elapsed_s,iso8601,speed_mph,speed_mps,gps_mps,accel_mps2,stationary,latitude,longitude\n"
            guard fm.createFile(atPath: url.path, contents: Data(header.utf8)) else {
                fileURL = nil
                return nil
            }
            handle = try? FileHandle(forWritingTo: url)
            try? handle?.seekToEnd()
            sessionStart = date
            fileURL = url
            return url
        }
    }

    func append(
        now: Date,
        speedMps: Double?,
        gpsMps: Double,
        accelMps2: Double,
        stationary: Bool,
        latitude: Double?,
        longitude: Double?
    ) {
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            let elapsed = now.timeIntervalSince(self.sessionStart)
            let mph = speedMps.map { $0 * 2.2369362921 }
            let speedMpsText = speedMps.map { Self.fixed($0) } ?? ""
            let mphText = mph.map { Self.fixed($0) } ?? ""
            let latitudeText = latitude.map { Self.coordinate($0) } ?? ""
            let longitudeText = longitude.map { Self.coordinate($0) } ?? ""
            let line = "\(Self.fixed(elapsed)),\(Self.iso.string(from: now)),\(mphText),\(speedMpsText),\(Self.fixed(gpsMps)),\(Self.fixed(accelMps2)),\(stationary ? 1 : 0),\(latitudeText),\(longitudeText)\n"
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    func stop() {
        queue.sync { stopLocked() }
    }

    private func stopLocked() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
