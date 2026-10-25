// Hosts the live camera preview inside SwiftUI.
// CameraPreviewView wraps the capture preview layer, and PreviewHostView keeps that layer sized to the view.
// ContentView uses it for the road camera during a drive.

import AVFoundation
import SwiftUI
import UIKit

/// SwiftUI wrapper that hosts a camera preview layer. `ContentView` uses one for the road camera.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        PreviewHostView(previewLayer: previewLayer)
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}
}

/// UIView that keeps an `AVCaptureVideoPreviewLayer` sized to the preview. `CameraPreviewView` creates it.
final class PreviewHostView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        if previewLayer.superlayer !== layer {
            previewLayer.removeFromSuperlayer()
            layer.addSublayer(previewLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
