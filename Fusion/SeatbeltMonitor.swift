// Decides whether the seatbelt alert should be showing from the front-camera boxes.
// A worn-belt box hides the alert, and a no-belt box shows it.
// A frame with neither box leaves the alert unchanged.
// DualCameraSession updates it on every driver frame.

import Foundation

/// One front-camera seatbelt box passed into `SeatbeltMonitor`.
struct SeatbeltObservation: Equatable {
    var label: String
    var confidence: Float
    /// Box area as a fraction of the frame, from 0 to 1.
    var area: Float
}

/// Shows the seatbelt alert when the front-camera model sees no belt, and hides it as soon as a belt box appears. `DualCameraSession` updates it every frame. A frame with neither box leaves the alert as it is.
final class SeatbeltMonitor {
    private(set) var unbuckled = false

    func reset() {
        unbuckled = false
    }

    func update(observations: [SeatbeltObservation]) -> Bool {
        switch Self.reading(observations) {
        case .unbuckled:
            unbuckled = true
        case .worn:
            unbuckled = false
        case .unknown:
            break
        }
        return unbuckled
    }

    /// True only when this frame includes a no-seatbelt box and no worn belt.
    static func isUnbuckled(_ observations: [SeatbeltObservation]) -> Bool {
        reading(observations) == .unbuckled
    }

    /// A seatbelt box means the belt is on, even if a no-seatbelt box is stronger
    /// or the worn box itself is faint. No belt box leaves the frame undecided.
    static func reading(_ observations: [SeatbeltObservation]) -> SeatbeltReading {
        if observations.contains(where: { isWornBelt($0.label) && $0.confidence >= wornConfidence }) {
            return .worn
        }
        if observations.contains(where: { isNoSeatbelt($0.label) && $0.confidence >= openConfidence }) {
            return .unbuckled
        }
        return .unknown
    }

    private static let wornConfidence: Float = 0.05
    private static let openConfidence: Float = 0.2

    private static func isNoSeatbelt(_ label: String) -> Bool {
        let name = label.lowercased()
        return name.contains("no-seatbelt") || name.contains("no seatbelt") || name.contains("unbuckled")
    }

    private static func isWornBelt(_ label: String) -> Bool {
        let name = label.lowercased()
        if isNoSeatbelt(name) { return false }
        return name.contains("seatbelt") || name.contains("buckled")
    }
}

/// Whether this frame shows a worn belt, no belt, or not enough evidence. `SeatbeltMonitor` keeps the previous alert on `.unknown`.
enum SeatbeltReading: Equatable {
    case unbuckled
    case worn
    case unknown
}
