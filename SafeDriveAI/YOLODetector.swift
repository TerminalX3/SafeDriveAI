// Runs a bundled YOLO Core ML model on one camera frame and returns labeled boxes.
// The road detector uses COCO class names.
// DualCameraSession keeps one detector for the road and one for the driver.
// A missing model file is reported as YOLODetectorError.

import CoreML
import CoreVideo
import Foundation
import Vision

/// One object found in a camera frame. Road and driver monitors filter these by label, and `DetectionOverlay` draws the boxes.
struct DetectedObject: Identifiable, Equatable {
    let id: UUID
    let label: String
    let confidence: Float
    /// Normalized Vision box (origin bottom-left, 0...1).
    let boundingBox: CGRect

    func labeled(_ label: String) -> DetectedObject {
        DetectedObject(id: id, label: label, confidence: confidence, boundingBox: boundingBox)
    }

    var centerY: CGFloat {
        boundingBox.midY
    }

    var aspectRatio: CGFloat {
        guard boundingBox.height > 0 else { return 0 }
        return boundingBox.width / boundingBox.height
    }

    var isRedLight: Bool { normalizedLabel == "red" }
    var isGreenLight: Bool { normalizedLabel == "green" }
    var isStopSign: Bool { normalizedLabel == "stop" || normalizedLabel == "stop sign" }
    var isTrafficLight: Bool { isRedLight || isGreenLight }
    var isUncoloredTrafficLight: Bool { normalizedLabel == "traffic light" }

    var normalizedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Box height in 0...1. Larger ≈ closer to the camera.
    var prominence: CGFloat {
        max(boundingBox.height, boundingBox.width * 0.6)
    }
}

/// Failure from loading a bundled Core ML model. `YOLODetector` throws this when the model file is missing.
enum YOLODetectorError: LocalizedError {
    case modelMissing(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let name):
            return "The \(name) Core ML model was not found in the app bundle."
        }
    }
}

/// Runs a bundled YOLO Core ML model on one camera frame and returns `DetectedObject` boxes. `DualCameraSession` keeps one for the road and one for the driver.
final class YOLODetector {
    private let visionModel: VNCoreMLModel
    private let classNames: [String]
    private let resourceName: String
    private let minimumConfidence: Float

    init(
        resourceName: String,
        classNames: [String],
        minimumConfidence: Float = 0.35,
        iouThreshold: Double = 0.7
    ) throws {
        self.resourceName = resourceName
        self.classNames = classNames
        self.minimumConfidence = minimumConfidence
        let mlModel = try Self.loadModel(named: resourceName)
        let visionModel = try VNCoreMLModel(for: mlModel)
        visionModel.inputImageFeatureName = "image"
        visionModel.featureProvider = YOLOThresholdProvider(
            iouThreshold: iouThreshold,
            confidenceThreshold: Double(minimumConfidence)
        )
        self.visionModel = visionModel
    }

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [DetectedObject] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        return parse(request.results).filter { $0.confidence >= minimumConfidence }
    }

    private func parse(_ results: [VNObservation]?) -> [DetectedObject] {
        guard let results, !results.isEmpty else { return [] }

        let recognized = results.compactMap { $0 as? VNRecognizedObjectObservation }
        if !recognized.isEmpty {
            return recognized.compactMap { observation in
                guard let top = observation.labels.first else { return nil }
                return DetectedObject(
                    id: UUID(),
                    label: displayName(for: top.identifier),
                    confidence: top.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }

        var confidenceArray: MLMultiArray?
        var coordinateArray: MLMultiArray?

        for observation in results {
            guard let feature = observation as? VNCoreMLFeatureValueObservation,
                  let array = feature.featureValue.multiArrayValue else { continue }
            switch feature.featureName {
            case "confidence":
                confidenceArray = array
            case "coordinates":
                coordinateArray = array
            default:
                break
            }
        }

        guard let confidenceArray, let coordinateArray else { return [] }
        return decodeYOLO(confidence: confidenceArray, coordinates: coordinateArray)
    }

    private func decodeYOLO(confidence: MLMultiArray, coordinates: MLMultiArray) -> [DetectedObject] {
        let confShape = confidence.shape.map(\.intValue)
        let coordShape = coordinates.shape.map(\.intValue)

        guard let layout = Self.layout(confidence: confShape, coordinates: coordShape) else { return [] }
        let boxCount = layout.boxCount
        let classCount = layout.classCount
        let confidenceIndexedByClassFirst = layout.confidenceClassFirst
        let coordHasBatch = layout.coordHasBatch
        let coordinatesAreBoxMajor = layout.coordinatesBoxMajor
        var detections: [DetectedObject] = []

        for boxIndex in 0..<boxCount {
            var bestClass = 0
            var bestScore: Float = 0

            for classIndex in 0..<min(classCount, classNames.count) {
                let score: Float
                if confidenceIndexedByClassFirst {
                    score = confShape.count >= 3
                        ? confidence[[0, classIndex, boxIndex] as [NSNumber]].floatValue
                        : confidence[[classIndex, boxIndex] as [NSNumber]].floatValue
                } else {
                    score = confShape.count >= 3
                        ? confidence[[0, boxIndex, classIndex] as [NSNumber]].floatValue
                        : confidence[[boxIndex, classIndex] as [NSNumber]].floatValue
                }

                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            guard bestScore >= minimumConfidence else { continue }

            let x: Double
            let y: Double
            let width: Double
            let height: Double
            if coordHasBatch, coordinatesAreBoxMajor {
                x = coordinates[[0, boxIndex, 0] as [NSNumber]].doubleValue
                y = coordinates[[0, boxIndex, 1] as [NSNumber]].doubleValue
                width = coordinates[[0, boxIndex, 2] as [NSNumber]].doubleValue
                height = coordinates[[0, boxIndex, 3] as [NSNumber]].doubleValue
            } else if coordHasBatch {
                x = coordinates[[0, 0, boxIndex] as [NSNumber]].doubleValue
                y = coordinates[[0, 1, boxIndex] as [NSNumber]].doubleValue
                width = coordinates[[0, 2, boxIndex] as [NSNumber]].doubleValue
                height = coordinates[[0, 3, boxIndex] as [NSNumber]].doubleValue
            } else if coordinatesAreBoxMajor {
                x = coordinates[[boxIndex, 0] as [NSNumber]].doubleValue
                y = coordinates[[boxIndex, 1] as [NSNumber]].doubleValue
                width = coordinates[[boxIndex, 2] as [NSNumber]].doubleValue
                height = coordinates[[boxIndex, 3] as [NSNumber]].doubleValue
            } else if coordShape.count == 2, coordShape[0] == 4 {
                x = coordinates[[0, boxIndex] as [NSNumber]].doubleValue
                y = coordinates[[1, boxIndex] as [NSNumber]].doubleValue
                width = coordinates[[2, boxIndex] as [NSNumber]].doubleValue
                height = coordinates[[3, boxIndex] as [NSNumber]].doubleValue
            } else {
                x = coordinates[[boxIndex, 0] as [NSNumber]].doubleValue
                y = coordinates[[boxIndex, 1] as [NSNumber]].doubleValue
                width = coordinates[[boxIndex, 2] as [NSNumber]].doubleValue
                height = coordinates[[boxIndex, 3] as [NSNumber]].doubleValue
            }

            let originX = x - width / 2
            let originY = y - height / 2
            let visionBox = CGRect(
                x: originX,
                y: 1 - (originY + height),
                width: width,
                height: height
            )

            detections.append(
                DetectedObject(
                    id: UUID(),
                    label: displayName(for: classNames[bestClass]),
                    confidence: bestScore,
                    boundingBox: visionBox
                )
            )
        }

        return detections
    }

    private func displayName(for identifier: String) -> String {
        let raw = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = Int(raw), classNames.indices.contains(index) {
            return normalizedDisplayName(classNames[index])
        }
        switch raw {
        case "stop sign", "stopsign":
            return "stop"
        default:
            let resolved = classNames.first { $0.lowercased() == raw } ?? identifier
            return normalizedDisplayName(resolved)
        }
    }

    private func normalizedDisplayName(_ name: String) -> String {
        name.lowercased() == "stop sign" ? "stop" : name
    }

    /// Ultralytics NMS exports confidence as `[boxes, classes]` and coordinates as `[boxes, 4]`.
    private static func layout(confidence confShape: [Int], coordinates coordShape: [Int]) -> YOLOLayout? {
        let confBatch = confShape.count == 3 && confShape[0] == 1
        let coordBatch = coordShape.count == 3 && coordShape[0] == 1
        let conf = confBatch ? Array(confShape.dropFirst()) : confShape
        let coord = coordBatch ? Array(coordShape.dropFirst()) : coordShape
        guard conf.count == 2, coord.count == 2 else { return nil }

        let coordinatesBoxMajor: Bool
        let boxCount: Int
        if coord[1] == 4 {
            coordinatesBoxMajor = true
            boxCount = coord[0]
        } else if coord[0] == 4 {
            coordinatesBoxMajor = false
            boxCount = coord[1]
        } else {
            return nil
        }
        guard boxCount > 0 else { return nil }

        let confidenceClassFirst: Bool
        let classCount: Int
        if conf[0] == boxCount, conf[1] != boxCount {
            confidenceClassFirst = false
            classCount = conf[1]
        } else if conf[1] == boxCount, conf[0] != boxCount {
            confidenceClassFirst = true
            classCount = conf[0]
        } else if conf[1] == boxCount {
            confidenceClassFirst = false
            classCount = conf[1]
        } else {
            return nil
        }
        guard classCount > 0 else { return nil }

        return YOLOLayout(
            boxCount: boxCount,
            classCount: classCount,
            confidenceClassFirst: confidenceClassFirst,
            coordHasBatch: coordBatch,
            coordinatesBoxMajor: coordinatesBoxMajor
        )
    }

    /// Class names stored in the model, in index order.
    static func bundledClassNames(resourceName: String) -> [String] {
        guard let model = try? loadModel(named: resourceName) else { return [] }
        let metadata = model.modelDescription.metadata
        let defined = metadata[.creatorDefinedKey] as? [String: String]
        return classNames(from: defined?["names"])
    }

    static func classNames(from raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var indexed: [(Int, String)] = []
        let pattern = #"(\d+)\s*:\s*'([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard match.numberOfRanges == 3,
                  let indexRange = Range(match.range(at: 1), in: raw),
                  let nameRange = Range(match.range(at: 2), in: raw),
                  let index = Int(raw[indexRange]) else { continue }
            indexed.append((index, String(raw[nameRange])))
        }
        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func loadModel(named resourceName: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine

        if let compiled = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
        if let package = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") {
            return try MLModel(contentsOf: package, configuration: configuration)
        }
        throw YOLODetectorError.modelMissing(resourceName)
    }
}

/// Shape of a YOLO output tensor, so box coordinates and class scores can be read in whichever order the model used.
private struct YOLOLayout {
    let boxCount: Int
    let classCount: Int
    let confidenceClassFirst: Bool
    let coordHasBatch: Bool
    let coordinatesBoxMajor: Bool
}

/// Supplies the model's IoU and confidence cutoffs as Core ML input features.
private final class YOLOThresholdProvider: NSObject, MLFeatureProvider {
    let iouThreshold: Double
    let confidenceThreshold: Double

    init(iouThreshold: Double, confidenceThreshold: Double) {
        self.iouThreshold = iouThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    var featureNames: Set<String> { ["iouThreshold", "confidenceThreshold"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "iouThreshold":
            return MLFeatureValue(double: iouThreshold)
        case "confidenceThreshold":
            return MLFeatureValue(double: confidenceThreshold)
        default:
            return nil
        }
    }
}

/// COCO class names in model-output order. The road `YOLODetector` uses this list to label each box.
enum COCOLabels {
    static let names = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
        "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
        "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
        "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
        "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
        "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
        "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
        "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]
}
