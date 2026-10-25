// Drawings shared by the product screens: a highway, a sensor car, a small map, a notification, landscape art, the weekly score chart, and the phone on the rotate prompt.
// The home screen and reports list use the weekly chart.
// The rotate prompt uses the phone graphic.
// The other scenes are artwork for onboarding.

import SwiftUI

/// Perspective highway with clouds, a skyline, and an optional car ahead. Its pieces are reused as onboarding artwork.
struct HighwayIllustration: View {
    var showsCar = true

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                CloudShape()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * 0.28, height: height * 0.12)
                    .offset(x: -width * 0.28, y: -height * 0.28)
                CloudShape()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: width * 0.22, height: height * 0.1)
                    .offset(x: width * 0.3, y: -height * 0.22)

                Skyline()
                    .frame(width: width * 0.72, height: height * 0.28)
                    .offset(y: -height * 0.02)

                Ellipse()
                    .fill(Color(red: 0.78, green: 0.88, blue: 0.72).opacity(0.95))
                    .frame(width: width * 0.55, height: height * 0.28)
                    .offset(x: -width * 0.32, y: height * 0.08)
                Ellipse()
                    .fill(Color(red: 0.74, green: 0.86, blue: 0.68).opacity(0.9))
                    .frame(width: width * 0.5, height: height * 0.24)
                    .offset(x: width * 0.34, y: height * 0.1)

                PerspectiveRoad()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.86, green: 0.91, blue: 0.95),
                                Color(red: 0.76, green: 0.84, blue: 0.91)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(RoadMarkings().stroke(Color.white.opacity(0.9), lineWidth: 2))
                    .overlay(LaneDashes())
                    .frame(width: width * 0.92, height: height * 0.62)
                    .offset(y: height * 0.2)

                if showsCar {
                    RearCar()
                        .frame(width: min(width * 0.34, 150), height: min(height * 0.28, 90))
                        .offset(y: height * 0.08)
                }
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

/// A cloud outline inside `HighwayIllustration`.
private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.midY * 0.5, width: rect.width * 0.55, height: rect.height * 0.7))
        path.addEllipse(in: CGRect(x: rect.width * 0.28, y: 0, width: rect.width * 0.48, height: rect.height * 0.85))
        path.addEllipse(in: CGRect(x: rect.width * 0.5, y: rect.height * 0.25, width: rect.width * 0.5, height: rect.height * 0.65))
        return path
    }
}

/// Building silhouettes along the horizon of `HighwayIllustration`.
private struct Skyline: View {
    private let heights: [CGFloat] = [28, 46, 34, 70, 42, 88, 56, 74, 40, 62, 36, 50]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.73, green: 0.83, blue: 0.91).opacity(0.85))
                    .frame(width: height > 70 ? 14 : 10, height: height)
            }
        }
    }
}

/// The tapering road surface in `HighwayIllustration`.
private struct PerspectiveRoad: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let neck = rect.width * 0.16
        path.move(to: CGPoint(x: rect.midX - neck / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Lane edges drawn on `PerspectiveRoad`.
private struct RoadMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let neck = rect.width * 0.16
        path.move(to: CGPoint(x: rect.midX - neck / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX + neck / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY))
        return path
    }
}

/// Dashed center line of `HighwayIllustration`.
private struct LaneDashes: View {
    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let height = geo.size.height
            ForEach(0..<5, id: \.self) { index in
                let t = CGFloat(index) / 5
                let y = height * (0.18 + t * 0.72)
                let dashWidth = 3 + t * 8
                let dashHeight = 8 + t * 16
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: dashWidth, height: dashHeight)
                    .position(x: midX, y: y)
            }
        }
    }
}

/// Car seen from behind, placed on `HighwayIllustration`.
struct RearCar: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.55, green: 0.68, blue: 0.8).opacity(0.28))
                .frame(width: 100, height: 16)
                .offset(y: 38)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.80, green: 0.88, blue: 0.96),
                            Color(red: 0.55, green: 0.70, blue: 0.86)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 112, height: 50)
                .offset(y: 10)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.66, green: 0.78, blue: 0.90))
                .frame(width: 76, height: 30)
                .offset(y: -12)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.80, green: 0.89, blue: 0.96))
                .frame(width: 60, height: 16)
                .offset(y: -12)
            Capsule()
                .fill(Color(red: 0.93, green: 0.42, blue: 0.45))
                .frame(width: 16, height: 8)
                .offset(x: -40, y: 16)
            Capsule()
                .fill(Color(red: 0.93, green: 0.42, blue: 0.45))
                .frame(width: 16, height: 8)
                .offset(x: 40, y: 16)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .frame(width: 22, height: 10)
                .offset(y: 24)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.25, green: 0.33, blue: 0.43))
                .frame(width: 11, height: 18)
                .offset(x: -54, y: 20)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.25, green: 0.33, blue: 0.43))
                .frame(width: 11, height: 18)
                .offset(x: 54, y: 20)
        }
    }
}

/// Car with sensor cones, used as artwork for what the cameras watch.
struct SensorCarIllustration: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.70, green: 0.88, blue: 0.74).opacity(0.55))
                .frame(width: 70, height: 110)
                .offset(x: -78, y: 8)
            Ellipse()
                .fill(VigilColor.blue.opacity(0.16))
                .frame(width: 78, height: 120)
                .offset(x: 78, y: 6)

            SensorCone()
                .fill(
                    LinearGradient(
                        colors: [VigilColor.blue.opacity(0.05), VigilColor.blue.opacity(0.38)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 130, height: 58)
                .offset(y: -78)

            SensorCone()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.45), VigilColor.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 108, height: 52)
                .rotationEffect(.degrees(180))
                .offset(y: 78)

            FrontCar()
                .frame(width: 168, height: 92)

            SensorPill(icon: "person.fill", title: "Front Camera")
                .offset(y: -108)
            SensorPill(icon: "location.fill", title: "GPS")
                .offset(x: 118, y: -8)
            SensorPill(icon: "road.lanes", title: "Road Camera")
                .offset(y: 108)
        }
        .frame(height: 250)
        .accessibilityHidden(true)
    }
}

/// One sensor beam in `SensorCarIllustration`.
private struct SensorCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Label pill next to a sensor beam in `SensorCarIllustration`.
private struct SensorPill: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(VigilColor.navy)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(VigilColor.line, lineWidth: 1))
        .shadow(color: VigilColor.shadow.opacity(0.05), radius: 6, y: 3)
    }
}

/// Front view of a car, drawn inside `SensorCarIllustration`.
struct FrontCar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.92, blue: 0.97),
                            Color(red: 0.62, green: 0.76, blue: 0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.78, green: 0.88, blue: 0.96))
                .frame(width: 92, height: 36)
                .offset(y: -16)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.45, green: 0.58, blue: 0.72))
                .frame(width: 36, height: 8)
                .offset(y: 8)
            Circle()
                .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color(red: 0.75, green: 0.84, blue: 0.93), lineWidth: 2))
                .offset(x: -48, y: 10)
            Circle()
                .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color(red: 0.75, green: 0.84, blue: 0.93), lineWidth: 2))
                .offset(x: 48, y: 10)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.28, green: 0.36, blue: 0.46))
                .frame(width: 10, height: 16)
                .offset(x: -72, y: 8)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.28, green: 0.36, blue: 0.46))
                .frame(width: 10, height: 16)
                .offset(x: 72, y: 8)
        }
    }
}

/// Small map drawing used to explain speed-limit tracking.
struct SpeedLimitMap: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapCanvas()
            RouteOverlay()
            VStack(spacing: 0) {
                Text("45")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(Color(red: 0.91, green: 0.33, blue: 0.38), lineWidth: 3))
            .padding(14)
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Map with a route and a 45 mile per hour speed limit")
    }
}

/// Background streets of `SpeedLimitMap`.
private struct MapCanvas: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18),
                with: .color(Color(red: 0.95, green: 0.96, blue: 0.97))
            )
            let scaleX = size.width / 240
            let scaleY = size.height / 156
            let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, Color)] = [
                (12, 16, 54, 36, Color(red: 0.90, green: 0.92, blue: 0.95)),
                (74, 16, 48, 28, Color(red: 0.88, green: 0.91, blue: 0.95)),
                (130, 18, 70, 40, Color(red: 0.91, green: 0.93, blue: 0.96)),
                (14, 64, 40, 34, Color(red: 0.80, green: 0.90, blue: 0.78)),
                (62, 60, 58, 42, Color(red: 0.89, green: 0.92, blue: 0.96)),
                (128, 70, 46, 30, Color(red: 0.90, green: 0.93, blue: 0.96)),
                (180, 68, 50, 36, Color(red: 0.87, green: 0.91, blue: 0.95)),
                (16, 112, 70, 30, Color(red: 0.82, green: 0.91, blue: 0.80)),
                (96, 114, 80, 28, Color(red: 0.90, green: 0.93, blue: 0.96))
            ]
            for block in blocks {
                let rect = CGRect(
                    x: block.0 * scaleX,
                    y: block.1 * scaleY,
                    width: block.2 * scaleX,
                    height: block.3 * scaleY
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(block.4))
            }
        }
    }
}

/// Highlighted route drawn on `SpeedLimitMap`.
private struct RouteOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let start = CGPoint(x: geo.size.width * 0.28, y: geo.size.height * 0.72)
            let mid = CGPoint(x: geo.size.width * 0.42, y: geo.size.height * 0.48)
            let end = CGPoint(x: geo.size.width * 0.78, y: geo.size.height * 0.36)
            Path { path in
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x, y: mid.y))
                path.addLine(to: end)
            }
            .stroke(VigilColor.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .overlay(Circle().fill(VigilColor.blue).frame(width: 8, height: 8))
                .position(start)
        }
    }
}

/// Sample phone notification used as onboarding artwork.
struct NotificationPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(height: 132)
                .padding(.horizontal, 18)
                .offset(y: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle().fill(VigilColor.blue)
                        VigilMark(size: 18)
                    }
                    .frame(width: 32, height: 32)
                    Text("SafeDriveAI")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VigilColor.navy)
                    Spacer()
                    Text("now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VigilColor.muted)
                }
                Text("Your drive is complete!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VigilColor.navy)
                    .padding(.leading, 42)
                Text("View your safety report.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(VigilColor.body)
                    .padding(.leading, 42)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(VigilColor.line, lineWidth: 1)
            )
            .shadow(color: VigilColor.shadow.opacity(0.08), radius: 16, y: 8)
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rolling hills and bushes used as decorative landscape art.
struct HabitsLandscape: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.90, blue: 0.98),
                        Color(red: 0.90, green: 0.95, blue: 0.98),
                        Color(red: 0.86, green: 0.93, blue: 0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                CloudShape()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * 0.42, height: 54)
                    .position(x: width * 0.22, y: height * 0.16)
                CloudShape()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * 0.34, height: 46)
                    .position(x: width * 0.78, y: height * 0.22)
                CloudShape()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: width * 0.5, height: 50)
                    .position(x: width * 0.55, y: height * 0.48)

                Hill(peak: 0.35)
                    .fill(Color(red: 0.78, green: 0.74, blue: 0.90).opacity(0.55))
                    .frame(height: height * 0.28)
                    .position(x: width * 0.5, y: height * 0.62)
                Hill(peak: 0.25)
                    .fill(Color(red: 0.71, green: 0.84, blue: 0.66))
                    .frame(height: height * 0.32)
                    .position(x: width * 0.48, y: height * 0.74)
                Hill(peak: 0.15)
                    .fill(Color(red: 0.80, green: 0.90, blue: 0.70))
                    .frame(height: height * 0.28)
                    .position(x: width * 0.5, y: height * 0.86)

                Bush()
                    .fill(Color(red: 0.55, green: 0.75, blue: 0.58))
                    .frame(width: 70, height: 36)
                    .position(x: width * 0.18, y: height * 0.78)
                Bush()
                    .fill(Color(red: 0.48, green: 0.70, blue: 0.55))
                    .frame(width: 54, height: 28)
                    .position(x: width * 0.72, y: height * 0.84)
                Bush()
                    .fill(Color(red: 0.50, green: 0.72, blue: 0.56))
                    .frame(width: 40, height: 22)
                    .position(x: width * 0.84, y: height * 0.9)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One hill shape inside `HabitsLandscape`.
private struct Hill: Shape {
    var peak: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.height * peak)
        )
        path.closeSubpath()
        return path
    }
}

/// One bush shape inside `HabitsLandscape`.
private struct Bush: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: rect.height * 0.35, width: rect.width * 0.55, height: rect.height * 0.65))
        path.addEllipse(in: CGRect(x: rect.width * 0.28, y: 0, width: rect.width * 0.48, height: rect.height * 0.8))
        path.addEllipse(in: CGRect(x: rect.width * 0.5, y: rect.height * 0.3, width: rect.width * 0.5, height: rect.height * 0.7))
        return path
    }
}

/// Header illustration available for the home screen.
struct HomeHeaderArt: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Skyline()
                    .frame(width: geo.size.width * 0.7, height: 54)
                    .offset(y: -8)
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width * 0.15, y: geo.size.height * 0.75))
                    path.addQuadCurve(
                        to: CGPoint(x: geo.size.width * 0.95, y: geo.size.height * 0.35),
                        control: CGPoint(x: geo.size.width * 0.55, y: geo.size.height * 0.15)
                    )
                }
                .stroke(Color(red: 0.75, green: 0.84, blue: 0.91), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                Ellipse()
                    .fill(Color(red: 0.78, green: 0.88, blue: 0.74).opacity(0.8))
                    .frame(width: 90, height: 28)
                    .offset(x: 20, y: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bar chart of recent drive scores. The home dashboard and the reports list both show it.
struct WeeklyTrendChart: View {
    var scores: [Double] = []
    var days: [String] = []

    private var entries: [(day: String, score: Double)] {
        Array(zip(days, scores))
    }

    var body: some View {
        if entries.isEmpty {
            Text("Complete a drive to see your trend.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VigilColor.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .trailing) {
                        Text("10")
                        Spacer()
                        Text("5")
                        Spacer()
                        Text("0")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VigilColor.muted)
                    .frame(width: 26, height: 108)

                    GeometryReader { geo in
                        let plot = geo.size
                        let points = chartPoints(in: plot)
                        ZStack(alignment: .topLeading) {
                            Path { path in
                                guard let first = points.first else { return }
                                path.move(to: CGPoint(x: first.x, y: plot.height))
                                path.addLine(to: first)
                                for point in points.dropFirst() {
                                    path.addLine(to: point)
                                }
                                if let last = points.last {
                                    path.addLine(to: CGPoint(x: last.x, y: plot.height))
                                }
                                path.closeSubpath()
                            }
                            .fill(
                                LinearGradient(
                                    colors: [VigilColor.blue.opacity(0.18), VigilColor.blue.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            Path { path in
                                guard let first = points.first else { return }
                                path.move(to: first)
                                for point in points.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                            .stroke(VigilColor.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                                Circle()
                                    .fill(VigilColor.blue)
                                    .frame(width: 8, height: 8)
                                    .position(point)
                                Text(entries[index].score.formatted(.number.precision(.fractionLength(1))))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(VigilColor.navy)
                                    .position(x: point.x, y: max(10, point.y - 14))
                            }
                        }
                    }
                    .frame(height: 118)
                }

                HStack(spacing: 0) {
                    Color.clear.frame(width: 32)
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Text(entry.day)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VigilColor.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Safety scores " + entries.map { String(format: "%.1f", $0.score) }.joined(separator: ", "))
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let minScore = 0.0
        let maxScore = 10.0
        let topInset: CGFloat = 18
        let plotHeight = size.height - topInset
        return entries.enumerated().map { index, entry in
            let x = size.width * (CGFloat(index) + 0.5) / CGFloat(entries.count)
            let t = min(1, max(0, (entry.score - minScore) / (maxScore - minScore)))
            let y = topInset + plotHeight * (1 - t)
            return CGPoint(x: x, y: y)
        }
    }
}

/// Phone graphic on the rotate prompt. `RotatePromptView` points it toward landscape or portrait.
struct PhoneRotateArt: View {
    var towardLandscape: Bool

    var body: some View {
        HStack(spacing: 22) {
            PhoneGlyph(landscape: false, highlighted: !towardLandscape)
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(VigilColor.blue)
            PhoneGlyph(landscape: true, highlighted: towardLandscape)
        }
        .accessibilityHidden(true)
    }
}

/// The phone outline drawn by `PhoneRotateArt`.
private struct PhoneGlyph: View {
    var landscape: Bool
    var highlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: landscape ? 12 : 16, style: .continuous)
            .stroke(highlighted ? VigilColor.blue : VigilColor.dot, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: landscape ? 12 : 16, style: .continuous)
                    .fill(highlighted ? VigilColor.iconWash : Color.white)
            )
            .frame(width: landscape ? 78 : 48, height: landscape ? 48 : 78)
            .overlay {
                if highlighted {
                    Image(systemName: landscape ? "steeringwheel" : "iphone")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VigilColor.blue)
                }
            }
    }
}
