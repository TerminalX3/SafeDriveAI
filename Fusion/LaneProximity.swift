// Measures how much of the frame a vehicle box covers and whether that box sits in the lane the camera is aimed down.
// FollowingDistanceMonitor uses both checks before it raises a too-close alert.
// Box edges are fractions of the image, from 0 to 1.

import Foundation

/// How large a vehicle looks, and whether it sits in the lane the camera is aimed down. `FollowingDistanceMonitor` uses both checks before a too-close alert. Boxes are normalized: 0 is the left or bottom edge, 1 is the right or top.
enum LaneProximity {
    /// Share of the frame covered by a box. Width and height are fractions of the image.
    static func screenFraction(width: Double, height: Double) -> Double {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    /// The hood hides about the lower half of a car that is close in front.
    /// `bottom` is the box's lower edge, 0 at the bottom of the frame.
    /// Once that edge sits in the lower part of the picture, count the hidden half.
    static func leadScreenFraction(width: Double, height: Double, bottom: Double) -> Double {
        let visible = screenFraction(width: width, height: height)
        guard bottom < 0.34 else { return visible }
        return min(1, visible * 2)
    }

    /// The phone points down this lane, so that lane is the middle of the picture.
    /// A vehicle ahead covers the center. A vehicle in another lane sits off to one side.
    static func isInDriverLane(minX: Double, maxX: Double, laneHalfWidth: Double = 0.14) -> Bool {
        guard maxX > minX, laneHalfWidth > 0 else { return false }
        let midX = (minX + maxX) / 2
        let coversForwardCenter = minX < 0.5 && maxX > 0.5
        return coversForwardCenter && abs(midX - 0.5) <= laneHalfWidth
    }
}
