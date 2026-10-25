// Decides when a look away from the road becomes a distraction alert.
// A single glance is ignored until the head stays turned for about two seconds, and the car must be moving faster than 5 mph.
// DualCameraSession feeds it head poses from the front camera.

import Foundation

/// Decides whether the driver is looking away from the road. `DualCameraSession` updates it from each front-camera head pose. The head must stay turned for about two seconds, and the car must be moving faster than 5 mph.
final class DistractionMonitor {
    private var turnedSince: TimeInterval?
    private var focusedSince: TimeInterval?
    private(set) var distracted = false

    static let movingMinimumMph = 5.0
    static let holdSeconds: TimeInterval = 2.0
    static let clearSeconds: TimeInterval = 0.75

    func reset() {
        turnedSince = nil
        focusedSince = nil
        distracted = false
    }

    /// `time` is seconds on a steady clock, such as `CACurrentMediaTime()`.
    func update(pose: HeadPose?, at time: TimeInterval) -> Bool {
        let turnedAway = pose.map(HeadPoseMath.isTurnedAway) ?? false
        if turnedAway {
            focusedSince = nil
            if turnedSince == nil {
                turnedSince = time
            }
            if !distracted, let turnedSince, time - turnedSince >= Self.holdSeconds {
                distracted = true
            }
        } else {
            turnedSince = nil
            guard distracted else { return false }
            if focusedSince == nil {
                focusedSince = time
            }
            if let focusedSince, time - focusedSince >= Self.clearSeconds {
                distracted = false
                self.focusedSince = nil
            }
        }
        return distracted
    }

    static func shouldAlert(distracted: Bool, speedMph: Double?) -> Bool {
        guard distracted, let speedMph else { return false }
        return speedMph > movingMinimumMph
    }
}
