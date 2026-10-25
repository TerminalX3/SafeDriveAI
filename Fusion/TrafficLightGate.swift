// Filters detector boxes before a lamp color is trusted.
// A vehicle signal is a tall stack or a wide row of lamps, and the signal for this lane sits near the middle of the view.
// Square pedestrian signs and walk symbols are rejected.
// TrafficLightColorizer and TrafficComplianceMonitor both call these checks.

import Foundation

/// Decides whether a detector box is a vehicle signal before any lamp color is read. `TrafficLightColorizer` uses the housing and lamp checks, and `TrafficComplianceMonitor` keeps signals facing this lane. Pedestrian signs and walk signals are close to square, so they never reach color detection.
enum TrafficLightGate {
    /// The signal facing this lane sits near the middle of the view, up above the road.
    /// Signals for the cross street sit off to the side and should not change the alert.
    static func isDriverSignal(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Bool {
        guard maxX > minX, maxY > minY else { return false }
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return abs(midX - 0.5) <= 0.22 && midY >= 0.40
    }

    static func isVehicleHousing(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        let aspect = width / height
        let verticalStack = aspect <= 0.68
        let horizontalRow = aspect >= 1.85
        return verticalStack || horizontalRow
    }

    /// Red or green lamp color. Yellow, orange, and the white walk symbol return nil
    /// so they cannot change the alert.
    static func lampColor(red: Double, green: Double, blue: Double) -> String? {
        if red > green * 1.15, blue < green * 0.55, green > 0.35, red > 0.4 {
            return nil
        }
        if green >= red * 0.72, green >= blue, green >= 0.45 {
            return "green"
        }
        if red > green * 1.4, red > blue * 1.4, red >= 0.45 {
            return "red"
        }
        return nil
    }
}
