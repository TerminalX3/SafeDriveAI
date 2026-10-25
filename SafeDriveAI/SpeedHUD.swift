// The speed badge drawn over the road camera.
// It shows the current speed, the posted limit, and whether the car is under or over that limit.
// ContentView places it on the drive screen.
// The numbers come from SpeedMonitor.

import CoreLocation
import MapKit
import SwiftUI

/// Speed, limit, and status badge drawn over the road camera. `ContentView` places it on the drive screen.
struct SpeedHUD: View {
    @ObservedObject var monitor: SpeedMonitor

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                currentSpeedBadge
                speedLimitSign
                Text(statusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let message = monitor.locationMessage {
                    Text(message)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                locationPreview
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .padding(10)
        .frame(minWidth: 116)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var currentSpeedBadge: some View {
        let speedValue = monitor.speedMph.map { Int($0.rounded()) }
        return VStack(spacing: 0) {
            if monitor.isSpeedInitializing, !monitor.authorizationDenied {
                Text("Init")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text(speedValue.map(String.init) ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Text(monitor.isSpeedInitializing && !monitor.authorizationDenied ? "speed" : "mph")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 72, height: 72)
        .background(speedFill, in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
    }

    private var speedLimitSign: some View {
        let limitText = monitor.speedLimitMph.map(String.init)
            ?? (monitor.isSearchingSpeedLimit ? "…" : "--")
        return VStack(spacing: 0) {
            Text(monitor.speedLimitIsEstimated ? "EST" : "LIMIT")
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
            Text(limitText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: monitor.speedLimitMph)
        }
        .foregroundStyle(.black)
        .frame(width: 56, height: 64)
        .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.red, lineWidth: 3.5)
        )
    }

    private var locationPreview: some View {
        Map(position: .constant(mapPosition)) {
            if let coordinate = monitor.coordinate {
                Annotation("You", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .disabled(true)
        .frame(width: 96, height: 96)
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var mapPosition: MapCameraPosition {
        guard let coordinate = monitor.coordinate else {
            return .automatic
        }
        return .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 280,
                heading: monitor.headingDegrees ?? 0,
                pitch: 0
            )
        )
    }

    private var speedFill: Color {
        switch monitor.status {
        case .underLimit, .atLimit:
            return Color.green.opacity(0.85)
        case .overLimit:
            return Color.red.opacity(0.9)
        case .unknown:
            return Color.white.opacity(0.18)
        }
    }

    private var statusTitle: String {
        switch monitor.status {
        case .underLimit:
            return "Under"
        case .atLimit:
            return "At limit"
        case .overLimit:
            return "Over"
        case .unknown:
            if monitor.authorizationDenied { return "No GPS" }
            if monitor.isSpeedInitializing { return "Starting" }
            return "…"
        }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .underLimit, .atLimit:
            return .green
        case .overLimit:
            return .red
        case .unknown:
            return .white.opacity(0.8)
        }
    }

    private var accessibilityText: String {
        let speed: String
        if monitor.isSpeedInitializing, !monitor.authorizationDenied {
            speed = "speed initializing"
        } else {
            speed = monitor.speedMph.map { "\(Int($0.rounded())) miles per hour" } ?? "speed unknown"
        }
        let limit: String
        if let mph = monitor.speedLimitMph {
            limit = monitor.speedLimitIsEstimated ? "estimated limit \(mph)" : "limit \(mph)"
        } else if monitor.isSearchingSpeedLimit {
            limit = "finding speed limit"
        } else {
            limit = "limit unknown"
        }
        return "\(speed), \(limit), \(statusTitle)"
    }
}
