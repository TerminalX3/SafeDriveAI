// Assigns red or green to a traffic-light box after the detector has found it.
// The box must be a tall stack or a wide row of lamps, so square pedestrian signs are dropped before any pixel is read.
// Yellow is not reported.
// DualCameraSession runs this on the road frame before compliance is checked.

import CoreGraphics
import CoreVideo
import Foundation

/// Colors a traffic-light box for `DualCameraSession` after the detector has called it a light and the box has the tall or wide shape of a vehicle signal. Pedestrian signs are square, so they are dropped before any pixel is read. Yellow is not reported.
enum TrafficLightColorizer {
    private static let vehicleLabels: Set<String> = ["car", "bus", "truck"]
    private static let minimumBandPixels = 3
    private static let minimumSaturation = 0.22
    private static let minimumValue = 0.35
    private static let minimumScore = 0.18
    private static let minimumScoreRatio = 1.4
    private static let minimumScoreGap = 0.06
    /// Wide boxes sitting in the lower part of a dashcam frame are taillights.
    private static let taillightAspect: CGFloat = 1.25
    private static let taillightMaxCenterY: CGFloat = 0.42

    static func refine(detections: [DetectedObject], pixelBuffer: CVPixelBuffer) -> [DetectedObject] {
        let vehicles = detections
            .filter { vehicleLabels.contains($0.normalizedLabel) }
            .map(\.boundingBox)

        return detections.compactMap { detection in
            if detection.isStopSign {
                return detection.labeled("stop")
            }
            guard detection.isUncoloredTrafficLight, detection.confidence >= 0.5 else { return nil }
            let box = detection.boundingBox
            guard TrafficLightGate.isVehicleHousing(width: Double(box.width), height: Double(box.height)) else { return nil }
            guard !isOnVehicle(box, vehicles: vehicles) else { return nil }
            guard !isLowWideTaillight(detection) else { return nil }
            guard let color = lampLabel(pixelBuffer: pixelBuffer, box: box) else { return nil }
            return detection.labeled(color)
        }
    }

    static func lampLabel(pixelBuffer: CVPixelBuffer, box: CGRect) -> String? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        return lampLabel(
            bgra: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            box: box
        )
    }

    static func lampLabel(
        bgra: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        box: CGRect
    ) -> String? {
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }
        let lampBox = box.insetBy(dx: box.width * 0.12, dy: box.height * 0.1)
        guard lampBox.width > 0, lampBox.height > 0 else { return nil }
        let rect = pixelRect(for: lampBox, width: width, height: height)
        guard rect.width >= 6, rect.height >= 6 else { return nil }

        let tall = rect.height >= rect.width
        var redBands = [[Double]](repeating: [], count: 3)
        var greenBands = [[Double]](repeating: [], count: 3)
        var bright: [(red: Double, green: Double, blue: Double, value: Double)] = []

        for y in rect.minY..<rect.maxY {
            let row = bgra.advanced(by: y * bytesPerRow)
            let alongHeight = (Double(y - rect.minY) + 0.5) / Double(rect.height)
            for x in rect.minX..<rect.maxX {
                let pixel = row.advanced(by: x * 4)
                let blue = Double(pixel[0]) / 255
                let green = Double(pixel[1]) / 255
                let red = Double(pixel[2]) / 255
                let maxChannel = max(red, green, blue)
                let minChannel = min(red, green, blue)
                guard maxChannel > 0 else { continue }
                let saturation = (maxChannel - minChannel) / maxChannel
                guard saturation >= minimumSaturation, maxChannel >= minimumValue else { continue }
                if maxChannel >= 0.55 {
                    bright.append((red, green, blue, maxChannel))
                }
                guard let hue = TrafficLightGate.lampColor(red: red, green: green, blue: blue) else { continue }

                let along = tall
                    ? alongHeight
                    : (Double(x - rect.minX) + 0.5) / Double(rect.width)
                let band = min(2, max(0, Int(along * 3)))
                let score = saturation * maxChannel
                if hue == "red" {
                    redBands[band].append(score)
                } else {
                    greenBands[band].append(score)
                }
            }
        }

        // Top (or left) band is the red lamp. Bottom (or right) band is the green lamp.
        // The middle band is where a yellow lamp would sit, and it is ignored.
        let redAtTop = bandScore(redBands[0])
        let greenAtBottom = bandScore(greenBands[2])
        if redAtTop >= minimumScore,
           redAtTop >= greenAtBottom * minimumScoreRatio,
           redAtTop - greenAtBottom >= minimumScoreGap {
            return "red"
        }
        if greenAtBottom >= minimumScore,
           greenAtBottom >= redAtTop * minimumScoreRatio,
           greenAtBottom - redAtTop >= minimumScoreGap {
            return "green"
        }
        return colorOfBrightest(bright)
    }

    /// Color of the brightest pixels when the housing test is tied, such as a box
    /// tight on one lamp. Yellow and orange average out to no color.
    private static func colorOfBrightest(_ pixels: [(red: Double, green: Double, blue: Double, value: Double)]) -> String? {
        guard pixels.count >= 8 else { return nil }
        let ranked = pixels.sorted { $0.value > $1.value }
        let chosen = ranked.prefix(max(8, ranked.count / 4))
        let count = Double(chosen.count)
        let red = chosen.reduce(0) { $0 + $1.red } / count
        let green = chosen.reduce(0) { $0 + $1.green } / count
        let blue = chosen.reduce(0) { $0 + $1.blue } / count
        return TrafficLightGate.lampColor(red: red, green: green, blue: blue)
    }

    private static func bandScore(_ values: [Double]) -> Double {
        guard values.count >= minimumBandPixels else { return 0 }
        let brightest = values.sorted(by: >).prefix(max(1, values.count / 4))
        return brightest.reduce(0, +) / Double(brightest.count)
    }

    private static func isOnVehicle(_ box: CGRect, vehicles: [CGRect]) -> Bool {
        let center = CGPoint(x: box.midX, y: box.midY)
        return vehicles.contains { $0.contains(center) }
    }

    private static func isLowWideTaillight(_ detection: DetectedObject) -> Bool {
        detection.aspectRatio >= taillightAspect && detection.centerY < taillightMaxCenterY
    }

    private static func pixelRect(for box: CGRect, width: Int, height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int) {
        let minX = clamp(Int((box.minX * CGFloat(width)).rounded()), min: 0, max: width - 1)
        let maxX = clamp(Int((box.maxX * CGFloat(width)).rounded()), min: minX + 1, max: width)
        let minY = clamp(Int(((1 - box.maxY) * CGFloat(height)).rounded()), min: 0, max: height - 1)
        let maxY = clamp(Int(((1 - box.minY) * CGFloat(height)).rounded()), min: minY + 1, max: height)
        return (minX, minY, maxX, maxY, maxX - minX, maxY - minY)
    }

    private static func clamp(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.min(upper, Swift.max(lower, value))
    }
}
