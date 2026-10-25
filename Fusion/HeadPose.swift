// Holds yaw and pitch for the driver's head and converts MediaPipe landmarks or a face matrix into those angles.
// DriverFacePose produces a pose for each front-camera frame.
// DistractionMonitor reads the angles to decide whether the driver is looking away.

import Foundation

/// Head angles in degrees that `DriverFacePose` returns and `DistractionMonitor` reads. Yaw is left and right. Pitch is up and down.
struct HeadPose: Equatable {
    var yawDegrees: Double
    var pitchDegrees: Double
    var rollDegrees: Double
}

/// Turns Face Landmarker landmarks, or its 4×4 face matrix, into a `HeadPose`. `DriverFacePose` calls it for each front-camera frame.
enum HeadPoseMath {
    /// Looking left or right past this angle counts as looking away.
    static let yawLimitDegrees = 35.0
    /// Looking down at a phone, or up and away, past this angle counts too.
    static let pitchLimitDegrees = 35.0

    static func isTurnedAway(_ pose: HeadPose) -> Bool {
        abs(pose.yawDegrees) > yawLimitDegrees || abs(pose.pitchDegrees) > pitchLimitDegrees
    }

    /// MediaPipe Face Mesh points. Index 1 is the nose, 33 and 263 are the
    /// outer eye corners, 10 is the forehead, and 152 is the chin.
    static func pose(landmarks: [(x: Double, y: Double, z: Double)]) -> HeadPose? {
        guard landmarks.count > 263 else { return nil }
        let nose = landmarks[1]
        let eyeA = landmarks[33]
        let eyeB = landmarks[263]
        let forehead = landmarks[10]
        let chin = landmarks[152]

        let eyeDx = eyeB.x - eyeA.x
        let eyeDy = eyeB.y - eyeA.y
        let eyeSpan = max(hypot(eyeDx, eyeDy), 0.0001)
        let midX = (eyeA.x + eyeB.x) / 2
        let midY = (eyeA.y + eyeB.y) / 2
        let alongEyes = ((nose.x - midX) * eyeDx + (nose.y - midY) * eyeDy) / eyeSpan
        let yaw = atan2(alongEyes, eyeSpan * 0.55) * 180 / .pi

        let faceHeight = max(chin.y - forehead.y, 0.0001)
        let noseDrop = (nose.y - forehead.y) / faceHeight
        // 0.53 is where the nose sits on a face that is looking straight ahead.
        let pitch = (noseDrop - 0.53) / 0.0055

        let roll = atan2(eyeDy, eyeDx) * 180 / .pi
        return HeadPose(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll)
    }

    /// The Face Landmarker matrix is 16 numbers, one row at a time.
    static func pose(matrix: [Double]) -> HeadPose? {
        guard matrix.count >= 16 else { return nil }
        let r00 = matrix[0]
        let r01 = matrix[1]
        let r02 = matrix[2]
        let r10 = matrix[4]
        let r11 = matrix[5]
        let r12 = matrix[6]
        let r20 = matrix[8]
        let r21 = matrix[9]
        let r22 = matrix[10]
        let yaw = atan2(r20, max(hypot(r00, r10), 0.0001)) * 180 / .pi
        let pitch = atan2(-r21, max(r22, 0.0001)) * 180 / .pi
        let roll = atan2(r01, max(r11, 0.0001)) * 180 / .pi
        _ = r02
        _ = r12
        return HeadPose(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll)
    }
}
