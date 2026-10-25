// Draws what the road camera found and the alerts the driver should see.
// Detector boxes are painted on the preview.
// Stop, light, seatbelt, and distraction alerts share one icon size and glow.
// ContentView places this overlay and the banners over the live image.

import SwiftUI

/// Draws detector boxes on top of the road preview. `ContentView` passes the latest road detections.
struct DetectionOverlay: View {
    let detections: [DetectedObject]
    var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = Self.viewRect(for: detection.boundingBox, imageSize: imageSize, in: geometry.size)
                let color: Color = color(for: detection)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(color, lineWidth: 3)
                    Text(label(for: detection))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: -22)
                }
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func label(for detection: DetectedObject) -> String {
        let name = detection.normalizedLabel
        if name == "too close" || name.hasSuffix(" s") {
            return detection.label
        }
        let percent = Int((detection.confidence * 100).rounded())
        return "\(detection.label) \(percent)%"
    }

    private func color(for detection: DetectedObject) -> Color {
        if detection.isGreenLight { return .green }
        if detection.isRedLight || detection.isStopSign { return .red }
        return .orange
    }

    /// Maps a Vision normalized box (origin bottom-left) onto an aspect-filled preview.
    static func viewRect(for boundingBox: CGRect, imageSize: CGSize = .zero, in viewSize: CGSize) -> CGRect {
        let imageRect = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )

        if imageSize.width > 1, imageSize.height > 1, viewSize.width > 1, viewSize.height > 1 {
            let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
            let displayedWidth = imageSize.width * scale
            let displayedHeight = imageSize.height * scale
            let xOffset = (displayedWidth - viewSize.width) / 2
            let yOffset = (displayedHeight - viewSize.height) / 2
            return CGRect(
                x: imageRect.minX * displayedWidth - xOffset,
                y: imageRect.minY * displayedHeight - yOffset,
                width: imageRect.width * displayedWidth,
                height: imageRect.height * displayedHeight
            )
        }

        return CGRect(
            x: imageRect.minX * viewSize.width,
            y: imageRect.minY * viewSize.height,
            width: imageRect.width * viewSize.width,
            height: imageRect.height * viewSize.height
        )
    }
}

/// Maps a `TrafficStatus` to the alert artwork name and spoken label. `DrivingAlertIconView` asks it what to show.
enum DrivingAlertIcon {
    static func name(for status: TrafficStatus) -> String? {
        switch status.kind {
        case .stopSignStop, .stopSignHeld, .stopComplete, .rollingStopViolation, .missedStopViolation:
            return "AlertStop"
        case .redStop, .redLightViolation:
            return "AlertRedLight"
        case .greenProceed, .greenWaiting:
            return "AlertGreenLight"
        default:
            return nil
        }
    }

    static func label(for name: String) -> String {
        switch name {
        case "AlertStop": return "Stop sign"
        case "AlertRedLight": return "Red light"
        case "AlertGreenLight": return "Green light"
        case "AlertSeatbelt": return "Seatbelt not worn"
        default: return "Alert"
        }
    }
}

/// Large stop-sign or traffic-light icon for the current road status. `ContentView` shows it over the preview.
struct DrivingAlertIconView: View {
    let status: TrafficStatus

    var body: some View {
        if let name = DrivingAlertIcon.name(for: status) {
            RoadAlertIcon(name: name, tint: alertTint(for: name), label: DrivingAlertIcon.label(for: name))
        }
    }

    private func alertTint(for name: String) -> Color {
        switch name {
        case "AlertGreenLight":
            return .green
        case "AlertStop", "AlertRedLight":
            return .red
        default:
            return .white
        }
    }
}

/// Distracted-driving icon shown over the road preview while the driver is looking away.
struct DistractedAlertIcon: View {
    var body: some View {
        RoadAlertIcon(name: "AlertDistracted", tint: .yellow, label: "Distracted driving")
    }
}

/// Seatbelt icon shown over the road preview while the belt is off.
struct SeatbeltAlertIcon: View {
    var body: some View {
        RoadAlertIcon(name: "AlertSeatbelt", tint: .red, label: "Seatbelt not worn")
    }
}

/// Shared size, glow, and fade for every road alert icon. The stop, light, seatbelt, and distraction icons all use it.
struct RoadAlertIcon: View {
    let name: String
    let tint: Color
    let label: String

    var body: some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 124, height: 164)
            .shadow(color: tint.opacity(0.9), radius: 16)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .accessibilityLabel(label)
            .transition(.scale.combined(with: .opacity))
    }
}

/// Short "Distracted" banner. `ContentView` shows it with the distracted icon.
struct DistractedBanner: View {
    var body: some View {
        AlertBanner(
            systemImage: "eye.slash.fill",
            text: "Distracted",
            color: Color(red: 0.86, green: 0.64, blue: 0.02).opacity(0.95)
        )
    }
}

/// Short "Seatbelt" banner. `ContentView` shows it with the seatbelt icon.
struct SeatbeltBanner: View {
    var body: some View {
        AlertBanner(systemImage: "figure.seated.seatbelt", text: "Seatbelt", color: .red.opacity(0.92))
    }
}

/// Colored pill with an SF Symbol and a short label. The distracted and seatbelt banners are built from it.
struct AlertBanner: View {
    let systemImage: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
            Text(text)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityLabel(text)
        .transition(.opacity)
    }
}

/// Text banner for the current stop sign, light, or following-distance status. `ContentView` shows it above the road preview.
struct TrafficComplianceBanner: View {
    let status: TrafficStatus

    var body: some View {
        if let text = status.bannerText {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title2.weight(.bold))
                Text(text)
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityLabel(text)
            .transition(.opacity)
        }
    }

    private var iconName: String {
        switch status.kind {
        case .redLightViolation, .rollingStopViolation, .missedStopViolation:
            return "exclamationmark.octagon.fill"
        case .followingTooClose:
            return "car.rear.and.collision"
        case .redStop, .stopSignStop, .stopSignHeld:
            return "hand.raised.fill"
        case .greenProceed, .stopComplete:
            return "checkmark.circle.fill"
        case .greenWaiting:
            return "arrow.forward.circle.fill"
        case .needGPS:
            return "location.slash.fill"
        case .clear:
            return "circle"
        }
    }

    private var background: Color {
        if status.isViolation { return .red.opacity(0.92) }
        switch status.kind {
        case .greenProceed, .greenWaiting, .stopComplete:
            return .green.opacity(0.82)
        case .redStop, .stopSignStop, .stopSignHeld:
            return .red.opacity(0.92)
        case .followingTooClose:
            return .orange.opacity(0.88)
        case .needGPS:
            return .black.opacity(0.72)
        default:
            return .black.opacity(0.72)
        }
    }
}
