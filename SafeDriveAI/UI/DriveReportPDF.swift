// Builds a one-page PDF of a finished drive, including the score summary and a map of the route.
// The drive detail screen uses that file for email and the system share sheet.

import MapKit
import UIKit

/// Builds a one-page PDF of a finished drive. The detail screen uses it for email and the share sheet.
enum DriveReportPDF {
    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func write(_ report: DriveReport) async -> URL? {
        let map = await mapImage(for: report)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeDriveAI-Report.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                draw(report, map: map, in: context.cgContext)
            }
            return url
        } catch {
            return nil
        }
    }

    private static func draw(_ report: DriveReport, map: UIImage?, in context: CGContext) {
        let navy = ui(31, 45, 72)
        let body = ui(90, 104, 128)
        let line = ui(226, 234, 242)
        let canvas = ui(245, 250, 253)

        context.setFillColor(navy.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: page.width, height: 88))
        text("SafeDriveAI", at: CGPoint(x: 48, y: 26), font: .systemFont(ofSize: 24, weight: .bold), color: .white)
        text("Drive Report", at: CGPoint(x: 48, y: 54), font: .systemFont(ofSize: 14, weight: .medium), color: UIColor.white.withAlphaComponent(0.82))

        let when = report.endedAt.formatted(date: .abbreviated, time: .shortened)
        let whenSize = (when as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)])
        text(when, at: CGPoint(x: page.width - 48 - whenSize.width, y: 38), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)

        text("Safety Score", at: CGPoint(x: 48, y: 112), font: .systemFont(ofSize: 13, weight: .semibold), color: body)
        let score = DriveReportFormat.score(report.overall)
        text(score, at: CGPoint(x: 48, y: 132), font: .systemFont(ofSize: 36, weight: .bold), color: scoreUIColor(report.overall))
        let scoreWidth = (score as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 36, weight: .bold)]).width
        text("/10", at: CGPoint(x: 54 + scoreWidth, y: 150), font: .systemFont(ofSize: 15, weight: .semibold), color: body)

        let trip = "\(DriveReportFormat.miles(report.distanceMeters))  ·  \(DriveReportFormat.duration(report.duration))"
        text(trip, at: CGPoint(x: 48, y: 184), font: .systemFont(ofSize: 14, weight: .medium), color: navy)

        let card = CGRect(x: 48, y: 208, width: page.width - 96, height: 248)
        context.setFillColor(canvas.cgColor)
        fillRounded(card, radius: 14, in: context)
        context.setStrokeColor(line.cgColor)
        context.setLineWidth(1)
        strokeRounded(card, radius: 14, in: context)

        var rowY = card.minY + 12
        for section in ReportSection.allCases {
            text(section.title, at: CGPoint(x: card.minX + 20, y: rowY), font: .systemFont(ofSize: 15, weight: .semibold), color: navy)
            text(countLine(report, section), at: CGPoint(x: card.minX + 20, y: rowY + 20), font: .systemFont(ofSize: 12, weight: .medium), color: body)
            let scoreText = scoreLabel(report, section)
            let font = UIFont.systemFont(ofSize: 16, weight: .bold)
            let width = (scoreText as NSString).size(withAttributes: [.font: font]).width
            let color = report.score(for: section).map(scoreUIColor) ?? body
            text(scoreText, at: CGPoint(x: card.maxX - 20 - width, y: rowY + 8), font: font, color: color)
            rowY += 38
        }

        text("Route", at: CGPoint(x: 48, y: 468), font: .systemFont(ofSize: 13, weight: .semibold), color: body)
        let mapRect = CGRect(x: 48, y: 488, width: page.width - 96, height: 180)
        context.setFillColor(line.cgColor)
        fillRounded(mapRect, radius: 14, in: context)
        if let map {
            context.saveGState()
            roundedPath(mapRect, radius: 14).addClip()
            map.draw(in: mapRect)
            context.restoreGState()
        } else {
            text("No location was recorded for this drive.", at: CGPoint(x: mapRect.minX + 18, y: mapRect.midY - 8), font: .systemFont(ofSize: 13, weight: .medium), color: body)
        }

        let legendY = mapRect.maxY + 16
        var legendX: CGFloat = 48
        legendX = legend(color: ui(39, 164, 112), title: "Under", x: legendX, y: legendY, in: context)
        legendX = legend(color: ui(214, 72, 78), title: "Over", x: legendX, y: legendY, in: context)
        legendX = legend(color: ui(158, 168, 180), title: "No limit", x: legendX, y: legendY, in: context)
        _ = legend(color: ui(242, 184, 28), title: "Violation", x: legendX, y: legendY, in: context)

        let footer = "SafeDriveAI  ·  One-page drive summary"
        let footerFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        let footerWidth = (footer as NSString).size(withAttributes: [.font: footerFont]).width
        text(footer, at: CGPoint(x: (page.width - footerWidth) / 2, y: page.height - 32), font: footerFont, color: body)
    }

    private static func mapImage(for report: DriveReport) async -> UIImage? {
        let pins = report.clips.compactMap { clip -> (CLLocationCoordinate2D, String)? in
            guard let coordinate = clip.coordinate else { return nil }
            return (coordinate, clip.section.title)
        }
        let latitudes = report.track.map(\.latitude) + pins.map(\.0.latitude)
        let longitudes = report.track.map(\.longitude) + pins.map(\.0.longitude)
        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else {
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.012, (maxLat - minLat) * 2.4),
                longitudeDelta: max(0.012, (maxLon - minLon) * 2.4)
            )
        )
        options.size = CGSize(width: 1064, height: 460)
        options.scale = 2
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        return UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { renderer in
            snapshot.image.draw(at: .zero)
            let context = renderer.cgContext
            context.setLineWidth(8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for segment in DriveScore.mapSegments(from: report.track) where segment.points.count >= 2 {
                context.setStrokeColor(bandColor(segment.band).cgColor)
                context.beginPath()
                for (index, point) in segment.points.enumerated() {
                    let spot = snapshot.point(for: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                    if index == 0 {
                        context.move(to: spot)
                    } else {
                        context.addLine(to: spot)
                    }
                }
                context.strokePath()
            }
            for pin in pins {
                let spot = snapshot.point(for: pin.0)
                let rect = CGRect(x: spot.x - 9, y: spot.y - 9, width: 18, height: 18)
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))
                context.setFillColor(ui(242, 184, 28).cgColor)
                context.fillEllipse(in: rect)
            }
        }
    }

    private static func countLine(_ report: DriveReport, _ section: ReportSection) -> String {
        switch section {
        case .stopSign:
            return counted(report.stopCount, singular: "violation", plural: "violations")
        case .trafficLight:
            return counted(report.lightCount, singular: "violation", plural: "violations")
        case .following:
            return counted(report.closeCount, singular: "alert", plural: "alerts")
        case .seatbelt:
            return counted(report.eventCount(for: .seatbelt), singular: "alert", plural: "alerts")
        case .distracted:
            return counted(report.eventCount(for: .distracted), singular: "alert", plural: "alerts")
        case .speedLimit:
            guard report.speedScore != nil else { return "No posted limit" }
            if report.overLimitSeconds == 0 { return "No time over the limit" }
            return "Over for \(DriveReportFormat.duration(TimeInterval(report.overLimitSeconds)))"
        }
    }

    private static func counted(_ count: Int, singular: String, plural: String) -> String {
        if count == 0 { return "No \(plural)" }
        if count == 1 { return "1 \(singular)" }
        return "\(count) \(plural)"
    }

    private static func scoreLabel(_ report: DriveReport, _ section: ReportSection) -> String {
        guard let value = report.score(for: section) else { return "—" }
        return "\(DriveReportFormat.score(value))/10"
    }

    private static func legend(color: UIColor, title: String, x: CGFloat, y: CGFloat, in context: CGContext) -> CGFloat {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x, y: y + 2, width: 8, height: 8))
        text(title, at: CGPoint(x: x + 14, y: y), font: .systemFont(ofSize: 11, weight: .semibold), color: ui(90, 104, 128))
        let width = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold)]).width
        return x + 14 + width + 18
    }

    private static func text(_ value: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (value as NSString).draw(at: point, withAttributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    private static func fillRounded(_ rect: CGRect, radius: CGFloat, in context: CGContext) {
        context.addPath(roundedPath(rect, radius: radius).cgPath)
        context.fillPath()
    }

    private static func strokeRounded(_ rect: CGRect, radius: CGFloat, in context: CGContext) {
        context.addPath(roundedPath(rect, radius: radius).cgPath)
        context.strokePath()
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: radius)
    }

    private static func scoreUIColor(_ score: Double) -> UIColor {
        if score >= 8 { return ui(39, 164, 112) }
        if score >= 6 { return ui(184, 128, 42) }
        return ui(214, 72, 78)
    }

    private static func bandColor(_ band: SpeedBand) -> UIColor {
        switch band {
        case .under: return ui(39, 164, 112)
        case .over: return ui(214, 72, 78)
        case .unknown: return ui(158, 168, 180)
        }
    }

    private static func ui(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}
