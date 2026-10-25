// Keeps a rolling buffer of camera frames and saves the moments around each driving event.
// Stop and light clips are stored when that approach becomes a violation.
// Following-distance, seatbelt, and distraction alerts keep the frames just before and after the alert.
// The finished buffer becomes the clips and score on the drive report.

import CoreLocation
import Foundation

/// Records the camera frames around each driving event for the drive report. `DualCameraSession` feeds it frames, and the report is saved when the drive ends. A stop or light clip is kept when that approach becomes a violation.
final class DriveRecorder: ObservableObject {
    static let snapshotInterval: TimeInterval = 1.0 / 18.0
    /// Frames kept from before a sign, light, or alert is first noticed.
    private static let lookback: TimeInterval = 8
    /// Frames kept after the violation itself. The approach does not extend this.
    private static let tail: TimeInterval = 2.5
    /// How much of the approach to keep while waiting to see if it is a violation.
    private static let rollingWindow: TimeInterval = 12
    /// Seconds of the approach kept once a violation is confirmed.
    private static let prelude: TimeInterval = 8
    private static let keptWindow: TimeInterval = 14
    /// A continuous too-close or speeding spell counts once. A new one starts
    /// only after this long back under the line.
    private static let episodeGap: TimeInterval = 8
    private static let relatchDelay: TimeInterval = 3
    /// Enough frames for the kept window at eighteen per second, with a little spare.
    private static let maxShots = 280

    /// One captured moment in the rolling frame buffer, with JPEG data from each camera.
    private struct Shot {
        var date: Date
        var front: Data?
        var back: Data?
    }

    /// A violation or alert whose frames are still being collected.
    private struct OpenClip {
        var id: UUID
        var section: ReportSection
        var message: String
        var startedAt: Date
        var closeAt: Date
        var keep: Bool
        var shots: [Shot]
        var latitude: Double? = nil
        var longitude: Double? = nil
    }

    private let queue = DispatchQueue(label: "DriveRecorder")
    private var began = false
    private var closed = false
    private var driveID = UUID()
    private var startedAt = Date()
    private var latestFront: Data?
    private var latestBack: Data?
    private var lastSnapshot = Date.distantPast
    private var ring: [Shot] = []
    private var openClips: [OpenClip] = []
    private var finishedClips: [ViolationClip] = []
    private var latchedUntil: [ReportSection: Date] = [:]
    private var counts: [ReportSection: Int] = [:]
    private var track: [SpeedTrackPoint] = []
    private var lastSampleAt = Date.distantPast
    private var knownMoving = 0
    private var overLimit = 0
    private var latestLatitude: Double?
    private var latestLongitude: Double?
    private var speedAssessed = false
    private var speedPoints = 0.0
    private var speedingEpisode = false
    private var speedingClearAt: Date?
    private var speedingPeakOver = 0
    private var followingEpisode = false
    private var followingClearAt: Date?
    private var seatbeltEpisode = false
    private var seatbeltClearAt: Date?
    private var distractedEpisode = false
    private var distractedClearAt: Date?

    func begin(camera: DualCameraSession) {
        camera.setReportHandler { [weak self] isFront, data, date in
            self?.ingest(isFront: isFront, jpeg: data, at: date)
        }
        queue.async { [weak self] in
            guard let self, !self.closed, !self.began else { return }
            self.began = true
            self.startedAt = Date()
            self.driveID = UUID()
            DriveReportArchive.prepare(self.driveID)
        }
    }

    func note(_ status: TrafficStatus) {
        let message = status.message
        let kind = status.kind
        queue.async { [weak self] in
            guard let self, self.began, !self.closed else { return }
            let now = Date()
            self.noteFollowing(kind: kind, message: message, at: now)
            if kind != .followingTooClose {
                if let section = self.watchedSection(for: kind) {
                    self.touch(section, at: now)
                }
                if let section = self.violationSection(for: kind) {
                    let recorded = TrafficStatus(kind: kind, message: message, isViolation: true).bannerText ?? message
                    self.commitViolation(section, message: recorded, at: now)
                }
            }
            self.closeFinished(at: now)
        }
    }

    func noteSeatbelt(unbuckled: Bool) {
        queue.async { [weak self] in
            guard let self, self.began, !self.closed else { return }
            let now = Date()
            if unbuckled {
                self.seatbeltClearAt = nil
                if !self.seatbeltEpisode {
                    let before = self.counts[.seatbelt] ?? 0
                    self.commitViolation(.seatbelt, message: "Seatbelt not worn", at: now)
                    if (self.counts[.seatbelt] ?? 0) > before {
                        self.seatbeltEpisode = true
                    }
                }
            } else if self.seatbeltEpisode {
                if self.seatbeltClearAt == nil {
                    self.seatbeltClearAt = now.addingTimeInterval(Self.episodeGap)
                } else if now >= self.seatbeltClearAt! {
                    self.seatbeltEpisode = false
                    self.seatbeltClearAt = nil
                }
            }
            self.closeFinished(at: now)
        }
    }

    func noteDistracted(_ distracted: Bool) {
        queue.async { [weak self] in
            guard let self, self.began, !self.closed else { return }
            let now = Date()
            if distracted {
                self.distractedClearAt = nil
                if !self.distractedEpisode {
                    let before = self.counts[.distracted] ?? 0
                    self.commitViolation(.distracted, message: "Distracted while driving", at: now)
                    if (self.counts[.distracted] ?? 0) > before {
                        self.distractedEpisode = true
                    }
                }
            } else if self.distractedEpisode {
                if self.distractedClearAt == nil {
                    self.distractedClearAt = now.addingTimeInterval(Self.episodeGap)
                } else if now >= self.distractedClearAt! {
                    self.distractedEpisode = false
                    self.distractedClearAt = nil
                }
            }
            self.closeFinished(at: now)
        }
    }

    func sample(mph: Double?, limitMph: Int?, coordinate: CLLocationCoordinate2D?) {
        let latitude = coordinate?.latitude
        let longitude = coordinate?.longitude
        queue.async { [weak self] in
            self?.recordSample(mph: mph, limitMph: limitMph, latitude: latitude, longitude: longitude)
        }
    }

    func finish(camera: DualCameraSession) -> DriveReport {
        camera.setReportHandler(nil)
        return queue.sync {
            closed = true
            if speedingEpisode {
                closeSpeedingEpisode()
            }
            for clip in openClips where clip.keep {
                finishedClips.append(finalize(clip))
            }
            openClips.removeAll()
            let report = makeReport()
            DriveReportArchive.save(report)
            return report
        }
    }

    private func ingest(isFront: Bool, jpeg: Data, at date: Date) {
        queue.async { [weak self] in
            guard let self, self.began, !self.closed else { return }
            if isFront {
                self.latestFront = jpeg
            } else {
                self.latestBack = jpeg
            }
            guard date.timeIntervalSince(self.lastSnapshot) >= Self.snapshotInterval else { return }
            self.lastSnapshot = date
            let shot = Shot(date: date, front: self.latestFront, back: self.latestBack)
            self.ring.append(shot)
            let cutoff = date.addingTimeInterval(-Self.lookback)
            self.ring.removeAll { $0.date < cutoff }
            self.append(shot)
            self.closeFinished(at: date)
        }
    }

    private func recordSample(mph: Double?, limitMph: Int?, latitude: Double?, longitude: Double?) {
        guard began, !closed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSampleAt) >= 0.9 else { return }
        lastSampleAt = now

        if let limitMph {
            speedAssessed = true
        }
        let overBy: Int?
        if DriveScore.countsTowardSpeedScore(speedMph: mph, limitMph: limitMph), let mph, let limitMph {
            knownMoving += 1
            let delta = Int(mph.rounded()) - limitMph
            if delta >= 1 {
                overLimit += 1
                overBy = delta
            } else {
                overBy = nil
            }
        } else {
            overBy = nil
        }
        if let overBy {
            noteSpeeding(overBy: overBy, at: now)
        } else if mph != nil {
            noteNotSpeeding(at: now)
        }

        guard let latitude, let longitude else { return }
        latestLatitude = latitude
        latestLongitude = longitude
        let band = SpeedBand.classify(speedMph: mph, limitMph: limitMph)
        let point = SpeedTrackPoint(
            latitude: latitude,
            longitude: longitude,
            speedMph: mph,
            limitMph: limitMph,
            band: band
        )
        if shouldAppend(point) {
            track.append(point)
        }
    }

    private func shouldAppend(_ point: SpeedTrackPoint) -> Bool {
        guard let last = track.last else { return true }
        if last.band != point.band { return true }
        return DriveScore.meters(from: last, to: point) >= 8
    }

    private func noteFollowing(kind: TrafficStatus.Kind, message: String, at date: Date) {
        guard kind == .followingTooClose else {
            guard followingEpisode else { return }
            if followingClearAt == nil {
                followingClearAt = date.addingTimeInterval(Self.episodeGap)
            } else if date >= followingClearAt! {
                followingEpisode = false
                followingClearAt = nil
            }
            return
        }
        followingClearAt = nil
        guard !followingEpisode else { return }
        let before = counts[.following] ?? 0
        commitViolation(.following, message: message, at: date)
        if (counts[.following] ?? 0) > before {
            followingEpisode = true
        }
    }

    private func noteSpeeding(overBy: Int, at date: Date) {
        speedingClearAt = nil
        speedingPeakOver = max(speedingPeakOver, overBy)
        speedingEpisode = true
    }

    private func noteNotSpeeding(at date: Date) {
        guard speedingEpisode else { return }
        if speedingClearAt == nil {
            speedingClearAt = date.addingTimeInterval(Self.episodeGap)
        } else if date >= speedingClearAt! {
            closeSpeedingEpisode()
        }
    }

    private func closeSpeedingEpisode() {
        speedPoints += DriveScore.speedingPoints(mphOver: speedingPeakOver)
        speedingEpisode = false
        speedingPeakOver = 0
        speedingClearAt = nil
    }

    private func watchedSection(for kind: TrafficStatus.Kind) -> ReportSection? {
        switch kind {
        case .stopSignStop, .stopSignHeld, .stopComplete, .rollingStopViolation, .missedStopViolation:
            return .stopSign
        case .redStop, .greenProceed, .greenWaiting, .redLightViolation:
            return .trafficLight
        default:
            return nil
        }
    }

    private func violationSection(for kind: TrafficStatus.Kind) -> ReportSection? {
        switch kind {
        case .rollingStopViolation, .missedStopViolation:
            return .stopSign
        case .redLightViolation:
            return .trafficLight
        case .followingTooClose:
            return .following
        default:
            return nil
        }
    }

    private func touch(_ section: ReportSection, at date: Date) {
        if let index = openClips.firstIndex(where: { $0.section == section }) {
            guard !openClips[index].keep else { return }
            openClips[index].closeAt = date.addingTimeInterval(Self.tail)
            return
        }
        guard !isLatched(section, at: date) else { return }
        openClips.append(makeClip(section: section, message: "", at: date, keep: false))
    }

    private func commitViolation(_ section: ReportSection, message: String, at date: Date) {
        if let index = openClips.firstIndex(where: { $0.section == section }) {
            guard !openClips[index].keep else { return }
            openClips[index].keep = true
            openClips[index].message = message
            openClips[index].closeAt = date.addingTimeInterval(Self.tail)
            openClips[index].latitude = latestLatitude
            openClips[index].longitude = latestLongitude
            let earliest = date.addingTimeInterval(-Self.prelude)
            openClips[index].shots.removeAll { $0.date < earliest }
            if let first = openClips[index].shots.first?.date {
                openClips[index].startedAt = first
            }
            counts[section, default: 0] += 1
            return
        }
        guard !isLatched(section, at: date) else { return }
        var clip = makeClip(section: section, message: message, at: date, keep: true)
        clip.closeAt = date.addingTimeInterval(Self.tail)
        clip.latitude = latestLatitude
        clip.longitude = latestLongitude
        openClips.append(clip)
        counts[section, default: 0] += 1
    }

    private func isLatched(_ section: ReportSection, at date: Date) -> Bool {
        guard let until = latchedUntil[section] else { return false }
        return date < until
    }

    private func makeClip(section: ReportSection, message: String, at date: Date, keep: Bool) -> OpenClip {
        let history = ring.filter { shot in
            date.timeIntervalSince(shot.date) <= Self.lookback && frameData(for: section, shot: shot) != nil
        }
        return OpenClip(
            id: UUID(),
            section: section,
            message: message,
            startedAt: history.first?.date ?? date,
            closeAt: date.addingTimeInterval(Self.tail),
            keep: keep,
            shots: history
        )
    }

    private func append(_ shot: Shot) {
        for index in openClips.indices {
            guard shot.date <= openClips[index].closeAt else { continue }
            guard frameData(for: openClips[index].section, shot: shot) != nil else { continue }
            openClips[index].shots.append(shot)
            let window = openClips[index].keep ? Self.keptWindow : Self.rollingWindow
            let cutoff = shot.date.addingTimeInterval(-window)
            openClips[index].shots.removeAll { $0.date < cutoff }
            if openClips[index].shots.count > Self.maxShots {
                openClips[index].shots.removeFirst(openClips[index].shots.count - Self.maxShots)
            }
        }
    }

    private func closeFinished(at date: Date) {
        var stillOpen: [OpenClip] = []
        for clip in openClips {
            if date > clip.closeAt {
                if clip.keep {
                    finishedClips.append(finalize(clip))
                    latchedUntil[clip.section] = date.addingTimeInterval(Self.relatchDelay)
                }
            } else {
                stillOpen.append(clip)
            }
        }
        openClips = stillOpen
    }

    private func frameData(for section: ReportSection, shot: Shot) -> Data? {
        section.savesRoad ? shot.back : shot.front
    }

    private func finalize(_ clip: OpenClip) -> ViolationClip {
        let directory = DriveReportArchive.clipDirectory(drive: driveID, clip: clip.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefix = clip.section.savesRoad ? "back" : "front"
        var count = 0
        for shot in clip.shots {
            guard let data = frameData(for: clip.section, shot: shot) else { continue }
            let name = String(format: "%03d.jpg", count)
            try? data.write(to: directory.appendingPathComponent("\(prefix)-\(name)"), options: .atomic)
            count += 1
        }
        let message = clip.message.isEmpty ? clip.section.emptyDetail : clip.message
        return ViolationClip(
            id: clip.id,
            section: clip.section,
            startedAt: clip.startedAt,
            message: message,
            frameCount: count,
            latitude: clip.latitude,
            longitude: clip.longitude
        )
    }

    private func makeReport() -> DriveReport {
        let score = DriveScore.make(DriveScoreInput(
            stopViolations: counts[.stopSign] ?? 0,
            lightViolations: counts[.trafficLight] ?? 0,
            closeAlerts: counts[.following] ?? 0,
            seatbeltAlerts: counts[.seatbelt] ?? 0,
            distractedAlerts: counts[.distracted] ?? 0,
            speedAssessed: speedAssessed,
            speedPoints: speedPoints
        ))
        return DriveReport(
            id: driveID,
            startedAt: startedAt,
            endedAt: Date(),
            distanceMeters: DriveScore.distanceMeters(track),
            overall: score.overall,
            stopScore: score.stopSigns,
            lightScore: score.trafficLights,
            speedScore: score.speedLimit,
            closeScore: score.tooClose,
            stopCount: counts[.stopSign] ?? 0,
            lightCount: counts[.trafficLight] ?? 0,
            closeCount: counts[.following] ?? 0,
            knownMovingSeconds: knownMoving,
            overLimitSeconds: overLimit,
            clipFrameInterval: Self.snapshotInterval,
            clips: finishedClips.sorted { $0.startedAt < $1.startedAt },
            track: track
        )
    }
}
