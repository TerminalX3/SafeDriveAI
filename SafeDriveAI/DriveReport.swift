// The saved record of one drive and the code that stores it on disk.
// A report holds scores, violation clips, and the speed track, grouped into sections such as stop signs and distraction.
// DriveReportArchive writes each drive under Documents.
// DriveReportStore is the list the home and reports screens observe.

import Combine
import CoreLocation
import Foundation

/// One scored category on a drive report, from stop signs through distraction. The detail screen groups clips and empty states by this.
enum ReportSection: String, Codable, CaseIterable, Identifiable {
    case stopSign
    case trafficLight
    case speedLimit
    case following
    case seatbelt
    case distracted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopSign: return "Stop Signs"
        case .trafficLight: return "Traffic Lights"
        case .speedLimit: return "Speed Limit"
        case .following: return "Too Close"
        case .seatbelt: return "Seatbelt"
        case .distracted: return "Distracted"
        }
    }

    var symbol: String {
        switch self {
        case .stopSign: return "hand.raised.fill"
        case .trafficLight: return "trafficlight"
        case .speedLimit: return "speedometer"
        case .following: return "car.fill"
        case .seatbelt: return "seatbelt"
        case .distracted: return "eye.slash.fill"
        }
    }

    /// Stop signs, lights, and following distance come from the road camera.
    /// The seatbelt clip comes from the driver camera.
    var savesRoad: Bool {
        switch self {
        case .stopSign, .trafficLight, .following:
            return true
        case .speedLimit, .seatbelt, .distracted:
            return false
        }
    }

    var emptyDetail: String {
        switch self {
        case .stopSign: return "No stop-sign violations on this drive."
        case .trafficLight: return "No red-light violations on this drive."
        case .speedLimit: return "No location was recorded for this drive."
        case .following: return "No following-distance alerts on this drive."
        case .seatbelt: return "The seatbelt stayed on for this drive."
        case .distracted: return "No distracted driving on this drive."
        }
    }
}

/// A saved clip of one violation or alert. `DriveReport` stores the metadata, and `ViolationClipPlayer` plays the frames.
struct ViolationClip: Codable, Identifiable, Equatable {
    var id: UUID
    var section: ReportSection
    var startedAt: Date
    var message: String
    var frameCount: Int
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The saved summary of one finished drive: scores, clips, and the speed track. `DriveReportArchive` writes it, and the reports tab reads it.
struct DriveReport: Codable, Identifiable, Equatable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var overall: Double
    var stopScore: Double
    var lightScore: Double
    var speedScore: Double?
    var closeScore: Double
    var stopCount: Int
    var lightCount: Int
    var closeCount: Int
    var knownMovingSeconds: Int
    var overLimitSeconds: Int
    var clipFrameInterval: TimeInterval
    var clips: [ViolationClip]
    var track: [SpeedTrackPoint]
    /// True only for reports saved while infractions were added up from zero.
    var usesPenaltyPoints: Bool = false

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var includedSpeed: Bool { speedScore != nil }

    var overallCaption: String? {
        includedSpeed ? nil : "No posted speed limit was available."
    }

    func score(for section: ReportSection) -> Double? {
        switch section {
        case .stopSign: return stopScore
        case .trafficLight: return lightScore
        case .speedLimit: return speedScore
        case .following: return closeScore
        case .seatbelt: return seatbeltScore
        case .distracted: return distractedScore
        }
    }

    /// Older reports were saved before seatbelt clips existed.
    var seatbeltScore: Double {
        categoryScore(alerts: clips.filter { $0.section == .seatbelt }.count, each: DriveScore.seatbeltPoints)
    }

    var distractedScore: Double {
        categoryScore(alerts: clips.filter { $0.section == .distracted }.count, each: DriveScore.distractedPoints)
    }

    private func categoryScore(alerts: Int, each: Double) -> Double {
        max(0, (10 - Double(alerts) * each) * 10).rounded() / 10
    }

    func eventCount(for section: ReportSection) -> Int {
        switch section {
        case .stopSign: return stopCount
        case .trafficLight: return lightCount
        case .speedLimit: return overLimitSeconds
        case .following: return closeCount
        case .seatbelt: return clips.filter { $0.section == .seatbelt }.count
        case .distracted: return clips.filter { $0.section == .distracted }.count
        }
    }

    func clips(for section: ReportSection) -> [ViolationClip] {
        clips.filter { $0.section == section }.sorted { $0.startedAt < $1.startedAt }
    }

    func subtitle(for section: ReportSection) -> String {
        switch section {
        case .stopSign:
            return countText(stopCount, singular: "violation", plural: "violations")
        case .trafficLight:
            return countText(lightCount, singular: "violation", plural: "violations")
        case .following:
            return countText(closeCount, singular: "alert", plural: "alerts")
        case .seatbelt:
            return countText(eventCount(for: .seatbelt), singular: "alert", plural: "alerts")
        case .distracted:
            return countText(eventCount(for: .distracted), singular: "alert", plural: "alerts")
        case .speedLimit:
            guard speedScore != nil else { return "No posted limit on this drive" }
            if overLimitSeconds == 0 { return "Within the limit while moving" }
            return "Over for \(DriveReportFormat.duration(TimeInterval(overLimitSeconds)))"
        }
    }

    var weakSections: [ReportSection] {
        ReportSection.allCases.filter { section in
            guard let score = score(for: section) else { return false }
            return score < 8
        }
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        if count == 0 { return "No \(plural)" }
        if count == 1 { return "1 \(singular)" }
        return "\(count) \(plural)"
    }
}

extension DriveReport {
    /// JSON keys for a saved report. Older files omit some scores, and decoding fills those in.
    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, distanceMeters, overall
        case stopScore, lightScore, speedScore, closeScore
        case stopCount, lightCount, closeCount
        case knownMovingSeconds, overLimitSeconds, clipFrameInterval
        case clips, track, usesPenaltyPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        overall = try container.decode(Double.self, forKey: .overall)
        stopScore = try container.decode(Double.self, forKey: .stopScore)
        lightScore = try container.decode(Double.self, forKey: .lightScore)
        speedScore = try container.decodeIfPresent(Double.self, forKey: .speedScore)
        closeScore = try container.decode(Double.self, forKey: .closeScore)
        stopCount = try container.decode(Int.self, forKey: .stopCount)
        lightCount = try container.decode(Int.self, forKey: .lightCount)
        closeCount = try container.decode(Int.self, forKey: .closeCount)
        knownMovingSeconds = try container.decode(Int.self, forKey: .knownMovingSeconds)
        overLimitSeconds = try container.decode(Int.self, forKey: .overLimitSeconds)
        clipFrameInterval = try container.decode(TimeInterval.self, forKey: .clipFrameInterval)
        clips = try container.decode([ViolationClip].self, forKey: .clips)
        track = try container.decode([SpeedTrackPoint].self, forKey: .track)
        usesPenaltyPoints = try container.decodeIfPresent(Bool.self, forKey: .usesPenaltyPoints) ?? false
        if usesPenaltyPoints {
            stopScore = DriveScore.scoreOutOfTen(fromPenalty: stopScore)
            lightScore = DriveScore.scoreOutOfTen(fromPenalty: lightScore)
            closeScore = DriveScore.scoreOutOfTen(fromPenalty: closeScore)
            if let speedScore {
                self.speedScore = DriveScore.scoreOutOfTen(fromPenalty: speedScore)
            }
            overall = averageOutOfTen
            usesPenaltyPoints = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(overall, forKey: .overall)
        try container.encode(stopScore, forKey: .stopScore)
        try container.encode(lightScore, forKey: .lightScore)
        try container.encode(speedScore, forKey: .speedScore)
        try container.encode(closeScore, forKey: .closeScore)
        try container.encode(stopCount, forKey: .stopCount)
        try container.encode(lightCount, forKey: .lightCount)
        try container.encode(closeCount, forKey: .closeCount)
        try container.encode(knownMovingSeconds, forKey: .knownMovingSeconds)
        try container.encode(overLimitSeconds, forKey: .overLimitSeconds)
        try container.encode(clipFrameInterval, forKey: .clipFrameInterval)
        try container.encode(clips, forKey: .clips)
        try container.encode(track, forKey: .track)
        try container.encode(false, forKey: .usesPenaltyPoints)
    }

    private var averageOutOfTen: Double {
        var parts = [stopScore, lightScore, closeScore, seatbeltScore, distractedScore]
        if let speedScore {
            parts.append(speedScore)
        }
        guard !parts.isEmpty else { return 10 }
        return (parts.reduce(0, +) / Double(parts.count) * 10).rounded() / 10
    }
}

/// Short text for scores, distance, duration, and drive titles. The reports list and the PDF both use it.
enum DriveReportFormat {
    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func miles(_ meters: Double) -> String {
        guard meters >= 40 else { return "—" }
        let miles = meters / 1609.344
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remain = minutes % 60
        if remain == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remain) min"
    }

    static func title(for date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(time)"
        }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day), \(time)"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}

/// Reads and writes each drive report under Documents/VigilReports. `DriveReportStore` loads the folder at startup.
enum DriveReportArchive {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VigilReports", isDirectory: true)
    }

    static func driveDirectory(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func clipDirectory(drive: UUID, clip: UUID) -> URL {
        driveDirectory(drive)
            .appendingPathComponent("clips", isDirectory: true)
            .appendingPathComponent(clip.uuidString, isDirectory: true)
    }

    static func prepare(_ id: UUID) {
        try? FileManager.default.createDirectory(
            at: driveDirectory(id),
            withIntermediateDirectories: true
        )
    }

    static func save(_ report: DriveReport) {
        prepare(report.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: driveDirectory(report.id).appendingPathComponent("report.json"), options: .atomic)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: driveDirectory(id))
    }

    static func loadAll() -> [DriveReport] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reports = directories.compactMap { directory -> DriveReport? in
            let url = directory.appendingPathComponent("report.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DriveReport.self, from: data)
        }
        return reports.sorted { $0.endedAt > $1.endedAt }
    }
}

/// In-memory list of saved drives for the home and reports screens. It loads from `DriveReportArchive` and writes changes back.
final class DriveReportStore: ObservableObject {
    @Published private(set) var reports: [DriveReport] = []

    init() {
        reports = DriveReportArchive.loadAll()
    }

    func add(_ report: DriveReport) {
        reports.removeAll { $0.id == report.id }
        reports.append(report)
        reports.sort { $0.endedAt > $1.endedAt }
    }

    func delete(_ id: UUID) {
        DriveReportArchive.delete(id)
        reports.removeAll { $0.id == id }
    }
}
