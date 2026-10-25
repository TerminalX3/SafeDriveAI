// Turns a finished drive into category scores and an overall score from 0 to 10.
// Deductions follow half of the New Jersey MVC point schedule for stops, lights, speeding, tailgating, seatbelts, and distraction.
// It also splits the saved track into map segments colored by whether the car was under or over the limit.
// DriveRecorder calls it when a drive ends, and the report map draws the segments.

import Foundation

/// Whether a saved location was under the limit, over it, or missing a speed or limit. `DriveScore` assigns the band, and the report map colors each stretch from it.
enum SpeedBand: String, Codable, Equatable {
    case under
    case over
    case unknown

    /// At the limit counts as under. Missing speed or a missing limit is unknown.
    static func classify(speedMph: Double?, limitMph: Int?) -> SpeedBand {
        guard let speedMph, let limitMph else { return .unknown }
        if Int(speedMph.rounded()) > limitMph { return .over }
        return .under
    }
}

/// A latitude and longitude on a colored speed-map stretch. `DriveScore.mapSegments` builds these from a drive track.
struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double
}

/// A run of map points that share one `SpeedBand`. The drive report and its PDF draw one polyline per segment.
struct SpeedMapSegment: Equatable {
    var band: SpeedBand
    var points: [GeoPoint]
}

/// One saved location on a drive, with speed and the posted limit. `DriveReport` stores the track, and `SpeedTrackMap` draws it.
struct SpeedTrackPoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var speedMph: Double?
    var limitMph: Int?
    var band: SpeedBand
}

/// Violation counts and speeding points for one finished drive. `DriveRecorder` fills this, and `DriveScore.make` turns it into category scores.
struct DriveScoreInput: Equatable {
    var stopViolations: Int = 0
    var lightViolations: Int = 0
    var closeAlerts: Int = 0
    var seatbeltAlerts: Int = 0
    var distractedAlerts: Int = 0
    /// True once a posted limit was known, so the speed category can be scored.
    var speedAssessed: Bool = false
    /// Half of New Jersey’s speeding points, one assessment per continuous episode.
    var speedPoints: Double = 0
}

/// Category scores and the overall score for one drive, each from 0 to 10. `DriveRecorder` copies these into the saved `DriveReport`.
struct DriveScoreResult: Equatable {
    var stopSigns: Double
    var trafficLights: Double
    var speedLimit: Double?
    var tooClose: Double
    var seatbelt: Double
    var distracted: Double
    var overall: Double
}

/// Scores a finished drive from violation counts, using half of the New Jersey MVC point schedule. `DriveRecorder` calls it when a drive ends, and the report map uses it to split the track by speed.
enum DriveScore {
    /// Parked samples are left out so a long red light does not dilute speeding.
    static let movingMinimumMph = 5

    /// Each category starts at 10 and stops at 0. Deductions are half of the
    /// New Jersey MVC schedule: a stop sign or traffic light is 1 point
    /// (N.J.S.A. 39:4-144 and 39:4-105), tailgating is 2.5 (39:4-89), and one
    /// continuous spell of speeding is 1, 2, or 2.5 points from how far over
    /// the limit it went (39:4-98). Speed is left out when no posted limit
    /// was available.
    static func make(_ input: DriveScoreInput) -> DriveScoreResult {
        let stopSigns = deducted(points: Double(input.stopViolations) * stopSignPoints)
        let trafficLights = deducted(points: Double(input.lightViolations) * trafficLightPoints)
        let tooClose = deducted(points: Double(input.closeAlerts) * tailgatingPoints)
        let seatbelt = deducted(points: Double(input.seatbeltAlerts) * seatbeltPoints)
        let distracted = deducted(points: Double(input.distractedAlerts) * distractedPoints)
        let speedLimit: Double? = input.speedAssessed ? deducted(points: input.speedPoints) : nil

        var parts = [stopSigns, trafficLights, tooClose, seatbelt, distracted]
        if let speedLimit {
            parts.append(speedLimit)
        }
        let overall = roundTenth(parts.reduce(0, +) / Double(parts.count))
        return DriveScoreResult(
            stopSigns: stopSigns,
            trafficLights: trafficLights,
            speedLimit: speedLimit,
            tooClose: tooClose,
            seatbelt: seatbelt,
            distracted: distracted,
            overall: overall
        )
    }

    static let stopSignPoints = 1.0
    static let trafficLightPoints = 1.0
    static let tailgatingPoints = 2.5
    /// One continuous stretch without a seatbelt. New Jersey does not assign
    /// license points for this, so the category drops by one.
    static let seatbeltPoints = 1.0
    /// One continuous stretch of distracted driving while moving.
    static let distractedPoints = 1.0

    /// Half of one citation's points from the fastest the car was over the limit.
    static func speedingPoints(mphOver: Int) -> Double {
        if mphOver >= 30 { return 2.5 }
        if mphOver >= 15 { return 2 }
        if mphOver >= 1 { return 1 }
        return 0
    }

    static func countsTowardSpeedScore(speedMph: Double?, limitMph: Int?) -> Bool {
        guard let speedMph, limitMph != nil else { return false }
        return Int(speedMph.rounded()) >= movingMinimumMph
    }

    /// Consecutive points of one color become one line. The first point of a
    /// new color starts that line, so the segments meet without overlapping.
    static func mapSegments(from points: [SpeedTrackPoint]) -> [SpeedMapSegment] {
        guard let first = points.first else { return [] }
        var segments: [SpeedMapSegment] = []
        var band = first.band
        var current = [GeoPoint(latitude: first.latitude, longitude: first.longitude)]

        for point in points.dropFirst() {
            let geo = GeoPoint(latitude: point.latitude, longitude: point.longitude)
            if point.band == band {
                current.append(geo)
            } else {
                if current.count >= 2 {
                    segments.append(SpeedMapSegment(band: band, points: current))
                }
                let bridge = current.last ?? geo
                band = point.band
                current = [bridge, geo]
            }
        }
        if current.count >= 2 {
            segments.append(SpeedMapSegment(band: band, points: current))
        } else if segments.isEmpty, let only = current.first {
            segments.append(SpeedMapSegment(band: band, points: [only]))
        }
        return segments
    }

    static func distanceMeters(_ points: [SpeedTrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += meters(from: points[index - 1], to: points[index])
        }
        return total
    }

    static func meters(from start: SpeedTrackPoint, to end: SpeedTrackPoint) -> Double {
        let earth = 6_371_000.0
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLat = (end.latitude - start.latitude) * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earth * asin(min(1, sqrt(haversine)))
    }

    /// Turns a saved penalty total back into a score out of 10.
    static func scoreOutOfTen(fromPenalty points: Double) -> Double {
        roundTenth(max(0, 10 - points))
    }

    private static func deducted(points: Double) -> Double {
        roundTenth(max(0, 10 - max(0, points)))
    }

    private static func roundTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
