// Decides stop-sign and traffic-light alerts from road detections and GPS speed.
// The camera arms the check, because the sign often leaves the frame at the stop line, and speed decides whether the car actually stopped.
// DualCameraSession updates it every frame.
// The drive screen shows the resulting banner.

import CoreGraphics
import Foundation
import QuartzCore

/// The banner state for the current stop sign, traffic light, or following-distance alert. `TrafficComplianceMonitor` and `FollowingDistanceMonitor` produce it, and the drive screen renders it.
struct TrafficStatus: Equatable {
    /// Which alert is active. The banner text and whether it counts as a violation come from this.
    enum Kind: Equatable {
        case clear
        case needGPS
        case greenProceed
        case greenWaiting
        case redStop
        case stopSignStop
        case stopSignHeld
        case stopComplete
        case redLightViolation
        case rollingStopViolation
        case missedStopViolation
        case followingTooClose
    }

    var kind: Kind = .clear
    var message: String = ""
    var isViolation: Bool = false

    static let clear = TrafficStatus(kind: .clear, message: "", isViolation: false)

    /// The only phrases shown for a stop sign or traffic light. Icons stay separate.
    var bannerText: String? {
        switch kind {
        case .redStop:
            return "Red light"
        case .greenProceed, .greenWaiting:
            return "Green light"
        case .stopSignStop, .stopSignHeld:
            return "Stop sign"
        case .redLightViolation:
            return "Traffic light violation."
        case .rollingStopViolation, .missedStopViolation:
            return "Stop sign violation."
        case .followingTooClose:
            return message.isEmpty ? nil : message
        default:
            return nil
        }
    }
}

/// Decides stop-sign and traffic-light alerts from road detections and GPS speed. `DualCameraSession` updates it each frame. The camera arms the check, and GPS speed decides whether the vehicle actually stopped after the sign leaves the frame.
final class TrafficComplianceMonitor {
    /// Where the car is in a stop-sign approach. The monitor advances this from how large the sign looks and how fast the car is moving.
    private enum StopPhase {
        case idle
        case approaching
        case atLine
        case holding
        case cleared
    }

    private let approachingProminence: CGFloat = 0.055
    private let closeProminence: CGFloat = 0.11
    private let stoppedSpeedMph = 2.8
    private let creepingSpeedMph = 5.5
    private let movingSpeedMph = 8.0
    private let runThroughSpeedMph = 14.0
    private let stopHoldDuration: CFTimeInterval = 1.0
    private let confirmHits = 4
    private let colorSwitchHits = 2
    /// A new lamp color has to hold for several frames before it replaces the one on screen.
    private let lightColorSwitchHits = 5
    private let seenGrace: CFTimeInterval = 1.6
    private let clearHold: CFTimeInterval = 1.3
    /// How long a red or green alert lingers after the light leaves the frame.
    private let lightMemoryDuration: CFTimeInterval = 2.5
    /// After a green light becomes red, keep the normal red alert before a run-through.
    private let greenToRedGrace: CFTimeInterval = 2.0
    private let memoryDuration: CFTimeInterval = 7.0
    private let atLineWindow: CFTimeInterval = 2.4
    private let rollingGrace: CFTimeInterval = 1.6
    private let clearedCooldown: CFTimeInterval = 2.5
    private let holdBlipGrace: CFTimeInterval = 0.7

    private(set) var confirmedLightKind: String?
    private(set) var isStopConfirmed = false

    private var lightKind: String?
    private var lightHitCount = 0
    private var challengerKind: String?
    private var challengerHits = 0
    private var lightVisible = false
    private var lightLastSeen: CFTimeInterval?
    private var lightProminence: CGFloat = 0
    private var redMovingSince: CFTimeInterval?
    private var greenStoppedSince: CFTimeInterval?
    private var lightReachedLine = false
    private var lightEverStopped = false
    private var redAfterGreenAt: CFTimeInterval?

    private var stopPhase: StopPhase = .idle
    private var stopHitCount = 0
    private var stopVisible = false
    private var stopLastSeen: CFTimeInterval?
    private var stopProminence: CGFloat = 0
    private var stopHoldStarted: CFTimeInterval?
    private var rollingSince: CFTimeInterval?
    private var holdMoveSince: CFTimeInterval?
    private var clearedAt: CFTimeInterval?
    private var pendingViolation: TrafficStatus?

    private var speedSamples: [(time: CFTimeInterval, mph: Double)] = []
    private var lastStatus = TrafficStatus.clear
    private var heldStatus = TrafficStatus.clear
    private var heldSince: CFTimeInterval = 0

    func reset() {
        lightKind = nil
        confirmedLightKind = nil
        lightHitCount = 0
        challengerKind = nil
        challengerHits = 0
        lightVisible = false
        lightLastSeen = nil
        lightProminence = 0
        redMovingSince = nil
        greenStoppedSince = nil
        lightReachedLine = false
        lightEverStopped = false
        redAfterGreenAt = nil
        stopPhase = .idle
        isStopConfirmed = false
        stopHitCount = 0
        stopVisible = false
        stopLastSeen = nil
        stopProminence = 0
        stopHoldStarted = nil
        rollingSince = nil
        holdMoveSince = nil
        clearedAt = nil
        speedSamples.removeAll()
        lastStatus = .clear
        heldStatus = .clear
        heldSince = 0
        pendingViolation = nil
    }

    func update(detections: [DetectedObject], speedMph: Double?, now: CFTimeInterval) -> TrafficStatus {
        recordSpeed(speedMph, now: now)

        let lights = detections.filter(\.isTrafficLight)
        let stops = detections.filter(\.isStopSign)
        let facing = lights.filter { light in
            let box = light.boundingBox
            return TrafficLightGate.isDriverSignal(
                minX: Double(box.minX),
                maxX: Double(box.maxX),
                minY: Double(box.minY),
                maxY: Double(box.maxY)
            )
        }
        let sawBothColors = facing.contains(where: \.isRedLight) && facing.contains(where: \.isGreenLight)
        let lightCandidates = sawBothColors ? facing.filter(\.isRedLight) : facing
        let light = lightCandidates.max { lhs, rhs in
            (lhs.prominence * CGFloat(lhs.confidence)) < (rhs.prominence * CGFloat(rhs.confidence))
        }
        let stop = stops.max { lhs, rhs in
            (lhs.prominence * CGFloat(lhs.confidence)) < (rhs.prominence * CGFloat(rhs.confidence))
        }

        updateLightMemory(light, conflictRed: sawBothColors, now: now)
        updateStopMemory(stop, now: now)
        // A stop sign replaced this green light. Don't bring the green alert back
        // after the sign drops out of frame.
        if confirmedLightKind == "green", !lightVisible, stopPhase != .idle {
            forgetLight()
        }

        let next: TrafficStatus
        let stopCompetes = stopPhase != .idle
        if let pendingViolation {
            self.pendingViolation = nil
            next = pendingViolation
        } else if speedMph == nil, hasArmedControl {
            next = TrafficStatus(
                kind: .needGPS,
                message: "GPS needed to verify a full stop.",
                isViolation: false
            )
        } else if let lightStatus = evaluateLight(speedMph: speedMph, now: now),
                  prefersLight(lightStatus, overStop: stopCompetes) {
            next = lightStatus
        } else if let stopStatus = evaluateStopSign(speedMph: speedMph, now: now) {
            next = stopStatus
        } else {
            next = .clear
        }

        return publish(next, now: now)
    }

    private func prefersLight(_ lightStatus: TrafficStatus, overStop stopCompetes: Bool) -> Bool {
        // Green stays up while the road is empty. A stop sign replaces it immediately.
        if confirmedLightKind == "green", stopCompetes {
            return false
        }
        let lightIsStopColor = confirmedLightKind == "red"
        return lightStatus.isViolation || lightIsStopColor || lightProminence >= closeProminence || !stopCompetes
    }

    /// The banner is already showing another control, so a stop sign should take over
    /// without waiting through a long streak of matching frames.
    private var stopCanTakeOver: Bool {
        switch heldStatus.kind {
        case .greenProceed, .greenWaiting, .needGPS:
            return true
        default:
            return false
        }
    }

    /// Keeps a light or stop alert on screen through a few empty frames.
    private func publish(_ status: TrafficStatus, now: CFTimeInterval) -> TrafficStatus {
        if status.kind == heldStatus.kind {
            if status.message != heldStatus.message, now - heldSince < clearHold, !status.isViolation {
                return heldStatus
            }
            if status.message != heldStatus.message {
                heldSince = now
            }
            heldStatus = status
            lastStatus = status
            return status
        }

        let keepPrevious = heldStatus.kind != .clear
            && status.kind == .clear
            && now - heldSince < clearHold
            && (confirmedLightKind != nil || stopPhase == .atLine || stopPhase == .holding || stopPhase == .approaching)
        if keepPrevious {
            return heldStatus
        }

        heldStatus = status
        heldSince = now
        lastStatus = status
        return status
    }

    private var hasArmedControl: Bool {
        confirmedLightKind != nil || stopPhase == .atLine || stopPhase == .holding
    }

    private func updateLightMemory(_ light: DetectedObject?, conflictRed: Bool, now: CFTimeInterval) {
        if let light, conflictRed || accepts(light) {
            let kind = light.isRedLight ? "red" : "green"
            lightVisible = true
            lightLastSeen = now
            lightProminence = max(lightProminence * 0.82, light.prominence)
            noteLightKind(kind, immediate: conflictRed && kind == "red", now: now)
            if light.prominence >= closeProminence {
                lightReachedLine = true
            }
            return
        }

        lightVisible = false
        if challengerHits > 0 {
            challengerHits -= 1
            if challengerHits == 0 {
                challengerKind = nil
            }
        }
        guard confirmedLightKind != nil || lightKind != nil else { return }

        if lightProminence >= closeProminence * 0.85 {
            lightReachedLine = true
        }

        let lastSeen = lightLastSeen ?? now
        if now - lastSeen >= lightMemoryDuration {
            expireLight(now: now)
        }
    }

    private func accepts(_ light: DetectedObject) -> Bool {
        let kind = light.isRedLight ? "red" : "green"
        let strong = light.confidence >= 0.4 && light.prominence >= approachingProminence * 0.7
        let readable = light.confidence >= 0.5 && light.prominence >= 0.018
        let refreshing = confirmedLightKind == kind && light.confidence >= 0.28
        return strong || readable || refreshing
    }

    /// A confirmed color stays until a different color wins several frames in a row.
    /// A frame that contains both colors confirms red immediately.
    private func noteLightKind(_ kind: String, immediate: Bool = false, now: CFTimeInterval) {
        guard kind == "red" || kind == "green" else { return }

        if immediate, kind == "red" {
            adoptConfirmedKind(kind, now: now)
            lightHitCount = confirmHits
            challengerKind = nil
            challengerHits = 0
            return
        }

        if let confirmedLightKind {
            if kind == confirmedLightKind {
                lightKind = kind
                lightHitCount = confirmHits
                challengerKind = nil
                challengerHits = 0
                return
            }
            if challengerKind == kind {
                challengerHits += 1
            } else {
                challengerKind = kind
                challengerHits = 1
            }
            guard challengerHits >= lightColorSwitchHits else { return }
            adoptConfirmedKind(kind, now: now)
            lightHitCount = colorSwitchHits
            challengerKind = nil
            challengerHits = 0
            return
        }

        if lightKind == kind {
            lightHitCount += 1
        } else if lightHitCount > 1 {
            lightHitCount -= 1
        } else {
            lightKind = kind
            lightHitCount = 1
        }
        if lightHitCount >= confirmHits, let lightKind {
            adoptConfirmedKind(lightKind, now: now)
        }
    }

    /// Green stays green and red stays red. A green that has just turned red
    /// gets a short grace before a run-through can be called.
    private func adoptConfirmedKind(_ kind: String, now: CFTimeInterval) {
        if kind == "red", confirmedLightKind == "green" {
            redAfterGreenAt = now
        } else if kind != "red" {
            redAfterGreenAt = nil
        }
        let changed = confirmedLightKind != kind
        lightKind = kind
        confirmedLightKind = kind
        if changed {
            redMovingSince = nil
            greenStoppedSince = nil
            lightEverStopped = false
        }
    }

    private func isInGreenToRedGrace(now: CFTimeInterval) -> Bool {
        guard let redAfterGreenAt else { return false }
        return now - redAfterGreenAt < greenToRedGrace
    }

    private func expireLight(now: CFTimeInterval) {
        let kind = confirmedLightKind
        let stopped = isEffectivelyStopped(now: now) || lightEverStopped || wasRecentlyStopped(now: now)
        let slowing = isSlowing(now: now)
        let speed = recentSpeed(now: now)

        if kind == "red", !isInGreenToRedGrace(now: now) {
            if !stopped, !slowing, speed >= runThroughSpeedMph, lightReachedLine {
                pendingViolation = TrafficStatus(
                    kind: .redLightViolation,
                    message: "Red light — you did not stop.",
                    isViolation: true
                )
            }
        }

        forgetLight()
    }

    private func forgetLight() {
        lightKind = nil
        confirmedLightKind = nil
        lightHitCount = 0
        challengerKind = nil
        challengerHits = 0
        lightLastSeen = nil
        lightProminence = 0
        redMovingSince = nil
        greenStoppedSince = nil
        lightReachedLine = false
        lightEverStopped = false
        redAfterGreenAt = nil
    }

    private func updateStopMemory(_ stop: DetectedObject?, now: CFTimeInterval) {
        if let stop, stop.confidence >= 0.4, stop.prominence >= approachingProminence * 0.8 {
            stopHitCount += 1
            if stopCanTakeOver, stopHitCount >= colorSwitchHits {
                stopHitCount = confirmHits
            }
            stopVisible = true
            stopLastSeen = now
            stopProminence = max(stopProminence * 0.45, stop.prominence)
            if stopHitCount >= confirmHits {
                isStopConfirmed = true
            }
            guard isStopConfirmed else { return }

            switch stopPhase {
            case .idle:
                stopPhase = stop.prominence >= closeProminence ? .atLine : .approaching
            case .approaching:
                if stop.prominence >= closeProminence {
                    stopPhase = .atLine
                }
            case .cleared:
                if let clearedAt, now - clearedAt > clearedCooldown, stop.prominence >= closeProminence {
                    stopPhase = .atLine
                    stopHoldStarted = nil
                    rollingSince = nil
                    holdMoveSince = nil
                }
            default:
                break
            }
            return
        }

        stopVisible = false
        guard isStopConfirmed || stopPhase != .idle else {
            if stopCanTakeOver, stopHitCount > 0 {
                stopHitCount -= 1
            } else {
                stopHitCount = 0
            }
            return
        }

        if stopPhase == .approaching, isStopConfirmed {
            stopPhase = .atLine
        }

        let lastSeen = stopLastSeen ?? now
        if now - lastSeen >= memoryDuration {
            expireStop(now: now)
        }
    }

    private func expireStop(now: CFTimeInterval) {
        let stopped = isEffectivelyStopped(now: now) || wasRecentlyStopped(now: now)
        let slowing = isSlowing(now: now)
        let speed = recentSpeed(now: now)

        if stopPhase == .holding || stopPhase == .cleared || stopped {
            stopPhase = .cleared
            clearedAt = now
            stopLastSeen = now
            return
        }

        if (stopPhase == .atLine || stopPhase == .approaching), !slowing, speed >= movingSpeedMph {
            pendingViolation = TrafficStatus(
                kind: .missedStopViolation,
                message: "Stop sign — you did not come to a complete stop.",
                isViolation: true
            )
        }
        forgetStop()
    }

    private func forgetStop() {
        stopPhase = .idle
        isStopConfirmed = false
        stopHitCount = 0
        stopLastSeen = nil
        stopProminence = 0
        stopHoldStarted = nil
        rollingSince = nil
        holdMoveSince = nil
    }

    private func evaluateLight(speedMph: Double?, now: CFTimeInterval) -> TrafficStatus? {
        guard let confirmedLightKind else { return nil }

        let speed = speedMph ?? -1
        let stopped = isEffectivelyStopped(now: now)
        let slowing = isSlowing(now: now)
        let moving = speed >= movingSpeedMph
        let secondsSinceSeen = now - (lightLastSeen ?? now)
        let tracking = lightVisible || secondsSinceSeen < seenGrace
        let atTheLine = lightReachedLine || !lightVisible
        let stillArriving = !tracking && secondsSinceSeen < atLineWindow

        if stopped {
            lightEverStopped = true
        }

        switch confirmedLightKind {
        case "red":
            greenStoppedSince = nil
            let redAlert = TrafficStatus(kind: .redStop, message: "Red light.", isViolation: false)

            if stopped || lightEverStopped && !tracking || slowing || speed < creepingSpeedMph || stillArriving
                || isInGreenToRedGrace(now: now) {
                redMovingSince = nil
                return redAlert
            }

            let runningVisible = lightVisible && atTheLine && moving
            let runningRemembered = !lightVisible && moving && speed >= runThroughSpeedMph && secondsSinceSeen >= atLineWindow
            if runningVisible || runningRemembered {
                if redMovingSince == nil { redMovingSince = now }
                let waited = redMovingSince.map { now - $0 >= rollingGrace } ?? false
                // The two seconds after green becomes red are the leeway. Don't add another wait on top.
                if redAfterGreenAt != nil || waited {
                    return TrafficStatus(
                        kind: .redLightViolation,
                        message: "Red light — stop. Speed \(Int(speed.rounded())) mph.",
                        isViolation: true
                    )
                }
            } else {
                redMovingSince = nil
            }

            return redAlert

        case "green":
            redMovingSince = nil
            greenStoppedSince = nil
            if tracking || lightProminence >= approachingProminence {
                return TrafficStatus(kind: .greenProceed, message: "Green light.", isViolation: false)
            }

        default:
            break
        }
        return nil
    }

    private func evaluateStopSign(speedMph: Double?, now: CFTimeInterval) -> TrafficStatus? {
        let speed = speedMph ?? -1
        let stopped = isEffectivelyStopped(now: now)
        let slowing = isSlowing(now: now)
        let moving = speed >= movingSpeedMph
        let secondsSinceSeen = now - (stopLastSeen ?? now)
        let stillArriving = !stopVisible && secondsSinceSeen < atLineWindow

        switch stopPhase {
        case .idle:
            return nil

        case .approaching:
            if stopped {
                stopPhase = .holding
                stopHoldStarted = now
                holdMoveSince = nil
                return TrafficStatus(kind: .stopSignHeld, message: "Hold a complete stop.", isViolation: false)
            }
            return TrafficStatus(kind: .stopSignStop, message: "Stop sign ahead — prepare to stop.", isViolation: false)

        case .atLine:
            if stopped {
                rollingSince = nil
                holdMoveSince = nil
                if stopHoldStarted == nil { stopHoldStarted = now }
                stopPhase = .holding
                return TrafficStatus(kind: .stopSignHeld, message: "Hold a complete stop.", isViolation: false)
            }
            if slowing || speed < creepingSpeedMph || stillArriving {
                rollingSince = nil
                return TrafficStatus(kind: .stopSignStop, message: "Stop sign — braking to a complete stop.", isViolation: false)
            }
            if moving {
                if rollingSince == nil { rollingSince = now }
                if let started = rollingSince, now - started >= rollingGrace {
                    return TrafficStatus(
                        kind: .rollingStopViolation,
                        message: "Stop sign — rolling through at \(Int(max(speed, 0).rounded())) mph. Come to a full stop.",
                        isViolation: true
                    )
                }
            } else {
                rollingSince = nil
            }
            return TrafficStatus(kind: .stopSignStop, message: "Stop sign — complete stop required.", isViolation: false)

        case .holding:
            if stopped {
                rollingSince = nil
                holdMoveSince = nil
                let started = stopHoldStarted ?? now
                stopHoldStarted = started
                if now - started >= stopHoldDuration {
                    stopPhase = .cleared
                    clearedAt = now
                    return TrafficStatus(kind: .stopComplete, message: "Complete stop — you may proceed when clear.", isViolation: false)
                }
                return TrafficStatus(kind: .stopSignHeld, message: "Holding stop…", isViolation: false)
            }

            if slowing || speed < creepingSpeedMph {
                holdMoveSince = nil
                return TrafficStatus(kind: .stopSignHeld, message: "Holding stop…", isViolation: false)
            }

            if holdMoveSince == nil { holdMoveSince = now }
            if let started = holdMoveSince, now - started >= holdBlipGrace, moving {
                stopPhase = .atLine
                stopHoldStarted = nil
                return TrafficStatus(
                    kind: .rollingStopViolation,
                    message: "Stop sign — that was not a complete stop.",
                    isViolation: true
                )
            }
            return TrafficStatus(kind: .stopSignStop, message: "Stop sign — complete stop required.", isViolation: false)

        case .cleared:
            if let clearedAt, now - clearedAt < 4 {
                return TrafficStatus(kind: .stopComplete, message: "Stop complete — proceed when clear.", isViolation: false)
            }
            forgetStop()
            return nil
        }
    }

    private func recordSpeed(_ speedMph: Double?, now: CFTimeInterval) {
        guard let speedMph else { return }
        speedSamples.append((now, speedMph))
        speedSamples.removeAll { now - $0.time > 3.0 }
    }

    private func recentSpeed(now: CFTimeInterval) -> Double {
        speedSamples.last { now - $0.time < 0.9 }?.mph ?? -1
    }

    private func isEffectivelyStopped(now: CFTimeInterval) -> Bool {
        let recent = speedSamples.filter { now - $0.time <= 0.8 }
        guard let last = recent.last else {
            return false
        }
        if last.mph <= stoppedSpeedMph { return true }
        let lowest = recent.map(\.mph).min() ?? last.mph
        return last.mph <= 4.2 && lowest <= stoppedSpeedMph
    }

    private func wasRecentlyStopped(now: CFTimeInterval) -> Bool {
        speedSamples.contains { now - $0.time < 3.0 && $0.mph <= stoppedSpeedMph }
    }

    private func isSlowing(now: CFTimeInterval) -> Bool {
        guard
            let current = speedSamples.last,
            let earlier = speedSamples.first(where: { current.time - $0.time >= 0.35 })
        else { return false }
        let dt = current.time - earlier.time
        guard dt > 0 else { return false }
        let drop = earlier.mph - current.mph
        return drop >= 1.4 && (drop / dt) >= 1.8
    }
}
