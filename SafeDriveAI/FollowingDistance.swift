// Warns when the vehicle ahead fills too much of the road camera and sits in this lane.
// The alert line is about 30 percent of the frame, and a hood that hides the lower half of the lead car is counted back in.
// DualCameraSession runs the monitor on each road detection frame.

import CoreGraphics
import Foundation

/// Thresholds `FollowingDistanceMonitor` uses to decide a lead car is too close. The car must cover about 30% of the frame and sit in the lane the camera is aimed down. A hood that cuts off the lower half of that car is counted back in.
enum FollowingDistanceCalibration {
    /// Width times height, as fractions of the image, after the hood adjustment.
    static let tooCloseFraction = 0.30
    /// Drop the warning once the car is clearly smaller than the alert line.
    static let clearFraction = 0.22
    static let laneHalfWidth: CGFloat = 0.14
    static let confirmFrames = 3
    /// Used only to ignore this car's hood along the bottom of the frame.
    static let horizonFromTop = 0.46
}

/// Result of one following-distance check: the alert to show, if any, and the lead vehicle box.
struct FollowingReading {
    var alert: TrafficStatus?
    var leadBox: DetectedObject?
}

/// Warns when a vehicle in this lane fills too much of the camera view. `DualCameraSession` runs it on each road-camera detection frame.
final class FollowingDistanceMonitor {
    private var closeFrames = 0
    private var clearFrames = 0
    private var missedFrames = 0
    private var alertActive = false
    private var lastLeadX: CGFloat?
    private var lastAlert: TrafficStatus?

    func reset() {
        closeFrames = 0
        clearFrames = 0
        missedFrames = 0
        alertActive = false
        lastLeadX = nil
        lastAlert = nil
    }

    func update(detections: [DetectedObject], now: CFTimeInterval) -> FollowingReading {
        _ = now
        guard let lead = leadVehicle(in: detections) else {
            noteMiss()
            return reading(alert: alertActive, lead: nil)
        }

        let sameLead = lastLeadX.map { abs($0 - lead.boundingBox.midX) < 0.15 } ?? true
        lastLeadX = lead.boundingBox.midX
        if !sameLead {
            closeFrames = 0
        }

        missedFrames = 0
        let box = lead.boundingBox
        let fraction = LaneProximity.leadScreenFraction(
            width: Double(box.width),
            height: Double(box.height),
            bottom: Double(box.minY)
        )
        let stillClose = alertActive && fraction >= FollowingDistanceCalibration.clearFraction
        if fraction >= FollowingDistanceCalibration.tooCloseFraction || stillClose {
            noteClose()
        } else {
            noteClear()
        }
        return reading(alert: alertActive, lead: lead)
    }

    private func noteClose() {
        closeFrames += 1
        clearFrames = 0
        if closeFrames >= FollowingDistanceCalibration.confirmFrames {
            alertActive = true
        }
    }

    private func noteClear() {
        closeFrames = 0
        clearFrames += 1
        if clearFrames >= 4 {
            alertActive = false
        }
    }

    private func noteMiss() {
        missedFrames += 1
        guard missedFrames >= 4 else { return }
        closeFrames = 0
        lastLeadX = nil
        lastAlert = nil
        alertActive = false
    }

    private func reading(alert: Bool, lead: DetectedObject?) -> FollowingReading {
        guard alert, let lead else {
            return FollowingReading(alert: alert ? lastAlert : nil, leadBox: nil)
        }
        let status = TrafficStatus(
            kind: .followingTooClose,
            message: "Too close — the car ahead fills your lane.",
            isViolation: false
        )
        lastAlert = status
        return FollowingReading(alert: status, leadBox: lead.labeled("too close"))
    }

    /// Largest vehicle in this lane, ignoring the hood.
    private func leadVehicle(in detections: [DetectedObject]) -> DetectedObject? {
        let vehicles = detections.filter { detection in
            guard ["car", "bus", "truck"].contains(detection.normalizedLabel) else { return false }
            guard detection.confidence >= 0.35 else { return false }
            let box = detection.boundingBox
            if GroundPlaneDistance.isEgoHood(
                minX: Double(box.minX),
                maxX: Double(box.maxX),
                minY: Double(box.minY),
                maxY: Double(box.maxY),
                horizonFromTop: FollowingDistanceCalibration.horizonFromTop
            ) {
                return false
            }
            return LaneProximity.isInDriverLane(
                minX: Double(box.minX),
                maxX: Double(box.maxX),
                laneHalfWidth: Double(FollowingDistanceCalibration.laneHalfWidth)
            )
        }
        return vehicles.max { lhs, rhs in
            LaneProximity.leadScreenFraction(
                width: Double(lhs.boundingBox.width),
                height: Double(lhs.boundingBox.height),
                bottom: Double(lhs.boundingBox.minY)
            )
                < LaneProximity.leadScreenFraction(
                    width: Double(rhs.boundingBox.width),
                    height: Double(rhs.boundingBox.height),
                    bottom: Double(rhs.boundingBox.minY)
                )
        }
    }
}
