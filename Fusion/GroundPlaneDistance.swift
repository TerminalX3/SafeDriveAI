// Estimates how far a point on a flat road is from its row in the camera image.
// It also recognizes this car's hood along the bottom of the frame.
// FollowingDistanceMonitor uses that hood check so the bumper is not counted as the vehicle ahead.

import Foundation

/// Distance and hood checks for a point on a flat road, from its row in the image. `FollowingDistanceMonitor` uses the hood test so this car's bumper is not treated as the car ahead. `bottomFromTop` and `horizonFromTop` are fractions of the image height, 0 at the top.
enum GroundPlaneDistance {
    static func meters(
        bottomFromTop: Double,
        imageHeight: Double,
        focalLengthY: Double,
        cameraHeight: Double,
        horizonFromTop: Double
    ) -> Double? {
        let belowHorizon = bottomFromTop - horizonFromTop
        guard belowHorizon > 0.012, imageHeight > 1, focalLengthY > 1, cameraHeight > 0 else { return nil }
        let pixelsBelowHorizon = belowHorizon * imageHeight
        let distance = focalLengthY * cameraHeight / pixelsBelowHorizon
        guard distance.isFinite, distance > 1.5, distance < 80 else { return nil }
        return distance
    }

    /// The camera looks over this car's hood. A hood detection is a shape along
    /// the bottom of the frame whose top stays near or below the horizon.
    /// A vehicle ahead, even one close enough to hide its tires, has its roof
    /// at or above the horizon.
    static func isEgoHood(
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double,
        horizonFromTop: Double
    ) -> Bool {
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0, horizonFromTop > 0.05, horizonFromTop < 0.95 else { return false }
        let horizonY = 1 - horizonFromTop
        // The roof of a car on the road sits at or above the horizon.
        if maxY < horizonY - 0.06 {
            return true
        }
        // The hood is cut off by the bottom edge and still does not clear the horizon.
        // A lead car close enough to hide its tires rises well above the horizon.
        let touchesBottom = minY < 0.08
        return touchesBottom && maxY < horizonY + 0.02
    }

    static func timeGapSeconds(distanceMeters: Double, speedMph: Double) -> Double? {
        let metersPerSecond = speedMph * 0.44704
        guard metersPerSecond > 1 else { return nil }
        let gap = distanceMeters / metersPerSecond
        guard gap.isFinite, gap > 0, gap < 20 else { return nil }
        return gap
    }
}
