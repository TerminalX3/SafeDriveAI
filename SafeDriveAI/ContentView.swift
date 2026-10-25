// The landscape screen shown while a drive is in progress.
// It lays out the road preview, detector boxes, speed readout, and alert banners.
// ActiveDriveView creates the camera session, speed monitor, and recorder and passes them in.

import AVFoundation
import SwiftUI

/// The landscape driving screen. `ActiveDriveView` shows it with the live camera session, speed monitor, and recorder.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var camera: DualCameraSession
    @ObservedObject var speedMonitor: SpeedMonitor
    @ObservedObject var recorder: DriveRecorder

    var body: some View {
        GeometryReader { geometry in
            cameraPane(
                previewLayer: camera.backPreviewLayer,
                size: geometry.size,
                detections: camera.backDetections,
                imageSize: camera.roadImageSize
            )
            .overlay(alignment: .top) {
                alertBanners
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(alignment: .bottom, spacing: 22) {
                    DrivingAlertIconView(status: camera.trafficStatus)
                    if camera.seatbeltUnbuckled {
                        SeatbeltAlertIcon()
                    }
                    if camera.distracted {
                        DistractedAlertIcon()
                    }
                    SpeedHUD(monitor: speedMonitor)
                        .fixedSize()
                }
                .animation(.easeInOut(duration: 0.2), value: camera.trafficStatus.kind)
                .animation(.easeInOut(duration: 0.2), value: camera.seatbeltUnbuckled)
                .animation(.easeInOut(duration: 0.2), value: camera.distracted)
                .padding(.bottom, 16)
                .padding(.trailing, 16)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .overlay(alignment: .center) {
            if camera.status != .running {
                statusOverlay
            }
        }
        .onAppear {
            camera.start()
            speedMonitor.start()
            camera.setVehicleSpeed(speedMonitor.speedMph)
        }
        .onDisappear {
            camera.stop()
            speedMonitor.stop()
        }
        .task {
            recorder.begin(camera: camera)
            while !Task.isCancelled {
                recorder.sample(
                    mph: speedMonitor.speedMph,
                    limitMph: speedMonitor.speedLimitMph,
                    coordinate: speedMonitor.coordinate
                )
                recorder.note(camera.trafficStatus)
                recorder.noteSeatbelt(unbuckled: camera.seatbeltUnbuckled)
                recorder.noteDistracted(camera.distracted)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: camera.trafficStatus) { _, status in
            recorder.note(status)
        }
        .onChange(of: camera.seatbeltUnbuckled) { _, unbuckled in
            recorder.noteSeatbelt(unbuckled: unbuckled)
        }
        .onChange(of: camera.distracted) { _, distracted in
            recorder.noteDistracted(distracted)
        }
        .onChange(of: speedMonitor.speedMph) { _, mph in
            camera.setVehicleSpeed(mph)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                speedMonitor.refreshLocationAccess()
            }
        }
        .background {
            CameraPreviewView(previewLayer: camera.frontPreviewLayer)
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var alertBanners: some View {
        let showsTraffic = camera.trafficStatus.bannerText != nil
        return VStack(spacing: 8) {
            TrafficComplianceBanner(status: camera.trafficStatus)
            if camera.seatbeltUnbuckled {
                SeatbeltBanner()
            }
            if camera.distracted {
                DistractedBanner()
            }
        }
        .padding(.top, showsTraffic || camera.seatbeltUnbuckled || camera.distracted ? 52 : 0)
        .animation(.easeInOut(duration: 0.2), value: camera.trafficStatus.kind)
        .animation(.easeInOut(duration: 0.2), value: camera.seatbeltUnbuckled)
        .animation(.easeInOut(duration: 0.2), value: camera.distracted)
    }

    private func cameraPane(
        previewLayer: AVCaptureVideoPreviewLayer,
        size: CGSize,
        detections: [DetectedObject],
        imageSize: CGSize
    ) -> some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(previewLayer: previewLayer)

            DetectionOverlay(detections: detections, imageSize: imageSize)

            if let error = camera.roadModelError {
                Text(error)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 12) {
            switch camera.status {
            case .idle, .requestingAccess:
                ProgressView()
                Text("Starting cameras…")
            case .denied:
                Text("Camera Access Needed")
                    .font(.headline)
                Text("Enable camera access in Settings to show the front and back cameras.")
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
            case .unsupported:
                Text("Dual Camera Unavailable")
                    .font(.headline)
                Text("This device does not support using the front and back cameras at the same time.")
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
            case .failed(let message):
                Text("Could Not Start Cameras")
                    .font(.headline)
                Text(message)
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
            case .running:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

#Preview {
    ContentPreview()
}

/// Preview host that builds the camera, speed, and recorder objects `ContentView` needs.
private struct ContentPreview: View {
    @StateObject private var camera = DualCameraSession()
    @StateObject private var speedMonitor = SpeedMonitor(logSensors: false)
    @StateObject private var recorder = DriveRecorder()

    var body: some View {
        ContentView(camera: camera, speedMonitor: speedMonitor, recorder: recorder)
    }
}
