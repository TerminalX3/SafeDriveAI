// Reads the driver's head angle from the front camera.
// MediaPipe handles faces that still show both eyes.
// A full profile is passed to Vision, which still returns yaw, pitch, and roll from the side.
// DualCameraSession sends the resulting pose to the distraction monitor.

import CoreVideo
import Foundation
import MediaPipeTasksVision
import UIKit
import Vision

/// Reads the driver's head angle from the front camera for `DualCameraSession`. MediaPipe covers faces that still show both eyes. A full profile is handed to Vision, which still returns yaw, pitch, and roll from the side.
final class DriverFacePose {
    private let landmarker: FaceLandmarker?
    private var lastTimestampMs = 0

    init(bundle: Bundle = .main) {
        guard let path = bundle.path(forResource: "face_landmarker", ofType: "task") else {
            landmarker = nil
            return
        }
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .video
        options.numFaces = 1
        options.outputFacialTransformationMatrixes = true
        options.minFaceDetectionConfidence = 0.5
        options.minFacePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        landmarker = try? FaceLandmarker(options: options)
    }

    var isReady: Bool { true }

    func pose(in pixelBuffer: CVPixelBuffer) -> HeadPose? {
        if let pose = mediaPipePose(in: pixelBuffer) {
            return pose
        }
        return Self.profilePose(in: pixelBuffer)
    }

    private func mediaPipePose(in pixelBuffer: CVPixelBuffer) -> HeadPose? {
        guard let landmarker else { return nil }
        let stamp = nextTimestampMs()
        guard let image = try? MPImage(pixelBuffer: pixelBuffer),
              let result = try? landmarker.detect(videoFrame: image, timestampInMilliseconds: stamp) else {
            return nil
        }
        return Self.pose(from: result)
    }

    /// Vision's face rectangle still locks on when the head is turned toward a profile.
    static func profilePose(in pixelBuffer: CVPixelBuffer) -> HeadPose? {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: {
                  $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
              }),
              face.confidence >= 0.2,
              let yaw = face.yaw?.doubleValue else { return nil }
        return HeadPose(
            yawDegrees: yaw * 180 / .pi,
            pitchDegrees: (face.pitch?.doubleValue ?? 0) * 180 / .pi,
            rollDegrees: (face.roll?.doubleValue ?? 0) * 180 / .pi
        )
    }

    static func pose(from result: FaceLandmarkerResult) -> HeadPose? {
        guard let index = result.faceLandmarks.indices.max(by: {
            area(result.faceLandmarks[$0]) < area(result.faceLandmarks[$1])
        }) else { return nil }
        if result.facialTransformationMatrixes.indices.contains(index),
           let pose = HeadPoseMath.pose(matrix: values(of: result.facialTransformationMatrixes[index])) {
            return pose
        }
        let points = result.faceLandmarks[index].map { landmark in
            (x: Double(landmark.x), y: Double(landmark.y), z: Double(landmark.z))
        }
        return HeadPoseMath.pose(landmarks: points)
    }

    private static func values(of matrix: TransformMatrix) -> [Double] {
        var values: [Double] = []
        values.reserveCapacity(Int(matrix.rows * matrix.columns))
        for row in 0..<matrix.rows {
            for column in 0..<matrix.columns {
                values.append(Double(matrix.value(atRow: row, column: column)))
            }
        }
        return values
    }

    private func nextTimestampMs() -> Int {
        let now = Int(CACurrentMediaTime() * 1000)
        let stamp = max(now, lastTimestampMs + 1)
        lastTimestampMs = stamp
        return stamp
    }

    private static func area(_ landmarks: [NormalizedLandmark]) -> Double {
        let xs = landmarks.map(\.x)
        let ys = landmarks.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return Double((maxX - minX) * (maxY - minY))
    }
}
