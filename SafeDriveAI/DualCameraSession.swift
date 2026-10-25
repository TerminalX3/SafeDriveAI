// Runs the front and back cameras together for the length of a drive.
// Each frame is detected, colored, and checked for lights, stop signs, following distance, seatbelts, and distraction.
// The results are published for the drive screen, and frames are handed to the recorder.

import AVFoundation
import Combine
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import QuartzCore
import UIKit

/// Runs the front and back cameras together during a drive. It detects the road and the driver, then publishes alerts for `ContentView`.
final class DualCameraSession: NSObject, ObservableObject {
    /// Whether the dual-camera session is idle, starting, running, or blocked. `ContentView` shows a message for the blocked cases.
    enum Status: Equatable {
        case idle
        case requestingAccess
        case running
        case denied
        case unsupported
        case failed(String)
    }

    let session = AVCaptureMultiCamSession()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()
    let backPreviewLayer = AVCaptureVideoPreviewLayer()

    @Published private(set) var status: Status = .idle
    @Published private(set) var isCapturing = false
    @Published private(set) var savedPairCount = 0
    @Published private(set) var backDetections: [DetectedObject] = []
    @Published private(set) var roadImageSize: CGSize = .zero
    @Published private(set) var roadModelError: String?
    @Published private(set) var trafficStatus: TrafficStatus = .clear
    @Published private(set) var seatbeltUnbuckled = false
    @Published private(set) var distracted = false
    @Published var lastSaveMessage: String?

    private let sessionQueue = DispatchQueue(label: "DualCameraSession.session")
    private let captureQueue = DispatchQueue(label: "DualCameraSession.frames")
    private let inferenceQueue = DispatchQueue(label: "DualCameraSession.inference", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let inferenceCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private let roadDetector: YOLODetector?
    private let seatbeltDetector: YOLODetector?
    private let trafficMonitor = TrafficComplianceMonitor()
    private let followingMonitor = FollowingDistanceMonitor()
    private let seatbeltMonitor = SeatbeltMonitor()
    private let distractionMonitor = DistractionMonitor()
    private let driverFacePose = DriverFacePose()

    private let minInferenceInterval: CFTimeInterval = 0.28
    /// A seatbelt check follows each road pass. The gap only keeps two checks
    /// from starting in the same instant; the road model still gets a turn
    /// between them.
    private let driverCheckInterval: CFTimeInterval = 0.12
    /// While the alert is up, belt checks run back to back so buckling clears it
    /// on the next frame instead of after another road pass.
    private let fastBeltInterval: CFTimeInterval = 0.05
    /// How long the road model waits for a front frame before taking the lock anyway.
    private let driverCheckWait: CFTimeInterval = 0.35
    /// The road model still runs during a fast clear if it has waited this long.
    private let roadStarvationLimit: CFTimeInterval = 0.55
    private var lastBackInferenceTime: CFTimeInterval = 0
    private var lastSeatbeltInferenceTime: CFTimeInterval = 0
    private var roadServedSinceDriverCheck = true
    private var driverWaitStarted: CFTimeInterval?
    private var clearBeltAlert = false
    private var isInferring = false
    private var vehicleSpeedMph: Double?

    private let frontVideoOutput = AVCaptureVideoDataOutput()
    private let backVideoOutput = AVCaptureVideoDataOutput()

    private var isConfigured = false
    private var captureTimer: DispatchSourceTimer?
    private var capturingEnabled = false
    private var awaitingPair = false
    private var pendingFrontJPEG: Data?
    private var pendingBackJPEG: Data?
    private var frontPreviewConnection: AVCaptureConnection?
    private var backPreviewConnection: AVCaptureConnection?
    private var backVideoConnection: AVCaptureConnection?
    private var previewRotationAngle: CGFloat = 0
    private var latchedSigns: [DetectedObject] = []
    private var latchedSignsAt: CFTimeInterval = 0
    private let reportQueue = DispatchQueue(label: "DualCameraSession.report", qos: .utility)
    private let reportCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var reportHandler: ((Bool, Data, Date) -> Void)?
    private var backReportBusy = false
    private var frontReportBusy = false
    private var lastBackReportTime: CFTimeInterval = 0
    private var lastFrontReportTime: CFTimeInterval = 0
    private let frontSnapshotInterval: TimeInterval = 1.0 / 6.0

    override init() {
        roadDetector = try? YOLODetector(
            resourceName: "Back",
            classNames: COCOLabels.names,
            minimumConfidence: 0.25
        )
        let frontClasses = YOLODetector.bundledClassNames(resourceName: "Front")
        seatbeltDetector = try? YOLODetector(
            resourceName: "Front",
            classNames: frontClasses.isEmpty ? ["no-seatbelt", "seatbelt"] : frontClasses,
            minimumConfidence: 0.05,
            iouThreshold: 0.99
        )
        super.init()
        if roadDetector == nil {
            roadModelError = "Road model (Back.mlpackage) could not be loaded."
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            status = .requestingAccess
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        setReportHandler(nil)
        stopCapturing()
        resetDetections()
        setIdleTimerDisabled(false)
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        if status == .running {
            status = .idle
        }
    }

    func setVehicleSpeed(_ mph: Double?) {
        inferenceQueue.async { [weak self] in
            self?.vehicleSpeedMph = mph
        }
    }

    func setReportHandler(_ handler: ((Bool, Data, Date) -> Void)?) {
        captureQueue.async { [weak self] in
            self?.reportHandler = handler
        }
    }

    func toggleCapturing() {
        if isCapturing {
            stopCapturing()
        } else {
            startCapturing()
        }
    }

    private func startCapturing() {
        guard status == .running, !isCapturing else { return }

        do {
            try ImageStore.prepareDirectories()
        } catch {
            lastSaveMessage = "Could not create image folders."
            return
        }

        isCapturing = true
        lastSaveMessage = "Saving to Files every 2 seconds."
        captureQueue.async { [weak self] in
            self?.capturingEnabled = true
        }
        requestPairSave()

        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.requestPairSave()
        }
        timer.resume()
        captureTimer = timer
    }

    private func stopCapturing() {
        captureTimer?.cancel()
        captureTimer = nil
        captureQueue.async { [weak self] in
            self?.capturingEnabled = false
            self?.awaitingPair = false
            self?.pendingFrontJPEG = nil
            self?.pendingBackJPEG = nil
        }
        if isCapturing {
            isCapturing = false
            lastSaveMessage = "Stopped. Saved \(savedPairCount) pair\(savedPairCount == 1 ? "" : "s")."
        }
    }

    private func requestPairSave() {
        captureQueue.async { [weak self] in
            guard let self, self.capturingEnabled else { return }
            self.awaitingPair = true
            self.pendingFrontJPEG = nil
            self.pendingBackJPEG = nil
        }
    }

    private func configureAndStart() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            status = .unsupported
            setIdleTimerDisabled(false)
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                self.session.startRunning()
                self.applyPreviewRotation(Self.currentVideoRotationAngle())
                DispatchQueue.main.async {
                    self.status = .running
                    self.setIdleTimerDisabled(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failed(error.localizedDescription)
                    self.setIdleTimerDisabled(false)
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        frontPreviewLayer.setSessionWithNoConnection(session)
        backPreviewLayer.setSessionWithNoConnection(session)
        frontPreviewLayer.videoGravity = .resizeAspectFill
        backPreviewLayer.videoGravity = .resizeAspectFill

        try addWideAngleCamera(
            position: .front,
            previewLayer: frontPreviewLayer,
            videoOutput: frontVideoOutput,
            mirrored: true
        )
        try addWideAngleCamera(
            position: .back,
            previewLayer: backPreviewLayer,
            videoOutput: backVideoOutput,
            mirrored: false
        )

        if session.hardwareCost > 1.0 {
            throw DualCameraError.hardwareCostExceeded
        }
    }

    private func addWideAngleCamera(
        position: AVCaptureDevice.Position,
        previewLayer: AVCaptureVideoPreviewLayer,
        videoOutput: AVCaptureVideoDataOutput,
        mirrored: Bool
    ) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw DualCameraError.cameraUnavailable(position)
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw DualCameraError.cannotAddInput(position)
        }
        session.addInputWithNoConnections(input)
        try configureWideAngleFormat(on: device)

        guard let port = input.ports.first(where: {
            $0.mediaType == .video
                && $0.sourceDeviceType == device.deviceType
                && $0.sourceDevicePosition == position
        }) else {
            throw DualCameraError.missingVideoPort(position)
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else {
            throw DualCameraError.cannotAddConnection(position)
        }
        session.addConnection(previewConnection)
        let previewAngle = position == .back
            ? Self.backPreviewRotation(from: Self.currentVideoRotationAngle())
            : Self.currentVideoRotationAngle()
        configureConnection(previewConnection, mirrored: mirrored, rotationAngle: previewAngle)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(videoOutput) else {
            throw DualCameraError.cannotAddOutput(position)
        }
        session.addOutputWithNoConnections(videoOutput)

        let videoConnection = AVCaptureConnection(inputPorts: [port], output: videoOutput)
        guard session.canAddConnection(videoConnection) else {
            throw DualCameraError.cannotAddConnection(position)
        }
        session.addConnection(videoConnection)
        configureConnection(videoConnection, mirrored: false, rotationAngle: 0)
        if position == .back, videoConnection.isCameraIntrinsicMatrixDeliverySupported {
            videoConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        videoConnection.isEnabled = true

        if position == .front {
            frontPreviewConnection = previewConnection
        } else {
            backPreviewConnection = previewConnection
            backVideoConnection = videoConnection
        }

        let availableFormats = videoOutput.availableVideoPixelFormatTypes
        if availableFormats.contains(kCVPixelFormatType_32BGRA) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        } else if let format = availableFormats.first {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: format
            ]
        }
    }

    private func configureWideAngleFormat(on device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let multiCamFormats = device.formats.filter(\.isMultiCamSupported)
        let preferred = multiCamFormats.min { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let leftScore = abs(Int(left.width) - 1280)
            let rightScore = abs(Int(right.width) - 1280)
            if leftScore == rightScore {
                return left.width > right.width
            }
            return leftScore < rightScore
        }

        if let preferred {
            device.activeFormat = preferred
        }

        device.videoZoomFactor = device.minAvailableVideoZoomFactor
    }

    @objc private func handleOrientationChange() {
        let angle = Self.currentVideoRotationAngle()
        sessionQueue.async { [weak self] in
            self?.applyPreviewRotation(angle)
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        previewRotationAngle = angle
        if let frontPreviewConnection {
            configureConnection(frontPreviewConnection, mirrored: true, rotationAngle: angle)
        }
        if let backPreviewConnection {
            configureConnection(
                backPreviewConnection,
                mirrored: false,
                rotationAngle: Self.backPreviewRotation(from: angle)
            )
        }
    }

    private static func backPreviewRotation(from frontAngle: CGFloat) -> CGFloat {
        let flipped = frontAngle + 180
        return flipped >= 360 ? flipped - 360 : flipped
    }

    private static func currentVideoRotationAngle() -> CGFloat {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation
            ?? .landscapeRight

        switch orientation {
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            return 90
        }
    }

    private func configureConnection(_ connection: AVCaptureConnection, mirrored: Bool, rotationAngle: CGFloat) {
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    private func finishPairIfReady() {
        guard let frontJPEG = pendingFrontJPEG, let backJPEG = pendingBackJPEG else { return }

        awaitingPair = false
        pendingFrontJPEG = nil
        pendingBackJPEG = nil

        let fileName = ImageStore.fileName(capturedAt: Date())
        do {
            try ImageStore.savePair(frontJPEG: frontJPEG, backJPEG: backJPEG, fileName: fileName)
            DispatchQueue.main.async {
                self.savedPairCount += 1
                self.lastSaveMessage = "Saved pair \(self.savedPairCount) to Files"
            }
        } catch {
            DispatchQueue.main.async {
                self.lastSaveMessage = error.localizedDescription
            }
        }
    }

    private func orientedImage(from pixelBuffer: CVPixelBuffer, mirror: Bool, rotation: CGFloat) -> CIImage {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if mirror {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        switch rotation {
        case 180:
            image = image.oriented(.down)
        case 90:
            image = image.oriented(.right)
        case 270:
            image = image.oriented(.left)
        default:
            break
        }
        if image.extent.origin != .zero {
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }
        return image
    }

    private func maybeDetect(from sampleBuffer: CMSampleBuffer, isFront: Bool) {
        if isFront {
            maybeDetectDriver(from: sampleBuffer)
            return
        }
        guard roadDetector != nil else { return }

        let now = CACurrentMediaTime()
        guard !isInferring else { return }
        if shouldLeaveTurnForDriver(at: now) { return }
        guard now - lastBackInferenceTime >= minInferenceInterval else { return }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pixelBuffer = copyPixelBuffer(source) else { return }

        isInferring = true
        lastBackInferenceTime = now
        roadServedSinceDriverCheck = true
        driverWaitStarted = nil
        let rotation = Self.backPreviewRotation(from: previewRotationAngle)

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            guard let detector = self.roadDetector else {
                self.captureQueue.async { self.isInferring = false }
                return
            }
            let detections: [DetectedObject]
            let rawDetections: [DetectedObject]
            let imageSize: CGSize
            if let inferenceBuffer = self.makeInferencePixelBuffer(from: pixelBuffer, mirror: false, rotation: rotation) {
                let raw = (try? detector.detect(in: inferenceBuffer, orientation: .up)) ?? []
                rawDetections = raw
                detections = TrafficLightColorizer.refine(detections: raw, pixelBuffer: inferenceBuffer)
                imageSize = CGSize(
                    width: CVPixelBufferGetWidth(inferenceBuffer),
                    height: CVPixelBufferGetHeight(inferenceBuffer)
                )
            } else {
                detections = []
                rawDetections = []
                imageSize = .zero
            }
            self.applyRoadDetections(
                detections,
                raw: rawDetections,
                imageSize: imageSize
            )
            self.captureQueue.async {
                self.isInferring = false
            }
        }
    }

    /// The road model yields when a front-camera check is due, until a front
    /// frame takes that turn. A stalled front camera does not freeze the road model.
    private func shouldLeaveTurnForDriver(at now: CFTimeInterval) -> Bool {
        guard driverCheckIsDue(at: now) else {
            driverWaitStarted = nil
            return false
        }
        if clearBeltAlert, now - lastBackInferenceTime >= roadStarvationLimit {
            return false
        }
        let roadHasHadATurn = roadServedSinceDriverCheck
        guard clearBeltAlert || roadHasHadATurn else {
            driverWaitStarted = nil
            return false
        }
        if driverWaitStarted == nil {
            driverWaitStarted = now
        }
        return now - (driverWaitStarted ?? now) < driverCheckWait
    }

    private func driverCheckIsDue(at now: CFTimeInterval) -> Bool {
        let interval = clearBeltAlert ? fastBeltInterval : driverCheckInterval
        return now - lastSeatbeltInferenceTime >= interval
    }

    /// Head pose and seatbelt run while the road model is idle, once per road turn.
    /// An active seatbelt alert does not wait for that road turn.
    private func maybeDetectDriver(from sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()
        let roadHasHadATurn = roadDetector == nil || roadServedSinceDriverCheck || clearBeltAlert
        guard !isInferring,
              roadHasHadATurn,
              driverCheckIsDue(at: now) else { return }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pixelBuffer = copyPixelBuffer(source) else { return }

        isInferring = true
        lastSeatbeltInferenceTime = now
        roadServedSinceDriverCheck = false
        driverWaitStarted = nil
        let rotation = previewRotationAngle
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let beltObservations: [SeatbeltObservation]
            if let beltBuffer = self.makeInferencePixelBuffer(from: pixelBuffer, mirror: false, rotation: rotation) {
                let belts = (try? self.seatbeltDetector?.detect(in: beltBuffer, orientation: .up)) ?? []
                beltObservations = belts.map { belt in
                    SeatbeltObservation(
                        label: belt.label,
                        confidence: belt.confidence,
                        area: Float(belt.boundingBox.width * belt.boundingBox.height)
                    )
                }
            } else {
                beltObservations = []
            }
            let showUnbuckled = self.seatbeltDetector == nil
                ? false
                : self.seatbeltMonitor.update(observations: beltObservations)
            DispatchQueue.main.async {
                if showUnbuckled != self.seatbeltUnbuckled {
                    self.seatbeltUnbuckled = showUnbuckled
                }
            }
            // Head pose waits until the belt result is published. While the
            // alert is up, skip it so the next belt check can start sooner.
            if !showUnbuckled {
                let pose: HeadPose?
                if let faceBuffer = self.makeInferencePixelBuffer(from: pixelBuffer, mirror: true, rotation: rotation) {
                    pose = self.driverFacePose.pose(in: faceBuffer)
                } else {
                    pose = nil
                }
                let distractedReading = self.distractionMonitor.update(pose: pose, at: CACurrentMediaTime())
                let showDistracted = DistractionMonitor.shouldAlert(
                    distracted: distractedReading,
                    speedMph: self.vehicleSpeedMph
                )
                DispatchQueue.main.async {
                    if showDistracted != self.distracted {
                        self.distracted = showDistracted
                    }
                }
            }
            self.captureQueue.async {
                self.clearBeltAlert = showUnbuckled
                self.isInferring = false
            }
        }
    }

    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        var copy: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            attributes as CFDictionary,
            &copy
        )
        guard status == kCVReturnSuccess, let copy else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount == 0 {
            guard let src = CVPixelBufferGetBaseAddress(source),
                  let dst = CVPixelBufferGetBaseAddress(copy) else { return nil }
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(copy)
            let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)
            for row in 0..<height {
                memcpy(dst.advanced(by: row * dstBytesPerRow), src.advanced(by: row * srcBytesPerRow), bytesPerRow)
            }
        } else {
            for plane in 0..<planeCount {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(copy, plane) else { continue }
                let rows = CVPixelBufferGetHeightOfPlane(source, plane)
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
                let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)
                for row in 0..<rows {
                    memcpy(dst.advanced(by: row * dstBytesPerRow), src.advanced(by: row * srcBytesPerRow), bytesPerRow)
                }
            }
        }

        return copy
    }

    private func makeInferencePixelBuffer(from pixelBuffer: CVPixelBuffer, mirror: Bool, rotation: CGFloat) -> CVPixelBuffer? {
        let image = orientedImage(from: pixelBuffer, mirror: mirror, rotation: rotation)

        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        guard width > 0, height > 0 else { return nil }

        var output: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }

        inferenceCIContext.render(image, to: output)
        return output
    }

    private func applyRoadDetections(
        _ detections: [DetectedObject],
        raw: [DetectedObject],
        imageSize: CGSize
    ) {
        let now = CACurrentMediaTime()
        let traffic = trafficMonitor.update(
            detections: detections,
            speedMph: vehicleSpeedMph,
            now: now
        )
        let following = followingMonitor.update(
            detections: raw,
            now: now
        )
        let status = Self.preferTraffic(traffic, over: following.alert)
        var confirmed = detections.filter { detection in
            if detection.isStopSign { return self.trafficMonitor.isStopConfirmed }
            if detection.isTrafficLight { return true }
            return false
        }
        if confirmed.isEmpty, now - latchedSignsAt < 1.3 {
            confirmed = latchedSigns
        } else if !confirmed.isEmpty {
            latchedSigns = confirmed
            latchedSignsAt = now
        }
        if status.kind == .followingTooClose, let lead = following.leadBox {
            confirmed.append(lead)
        }
        DispatchQueue.main.async {
            self.backDetections = confirmed
            self.roadImageSize = imageSize
            self.trafficStatus = status
        }
    }

    /// A red light or stop sign stays on screen. Following distance can replace a green light or a clear road.
    private static func preferTraffic(_ traffic: TrafficStatus, over following: TrafficStatus?) -> TrafficStatus {
        guard let following else { return traffic }
        switch traffic.kind {
        case .clear, .greenProceed, .greenWaiting:
            return following
        default:
            return traffic
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        let apply = {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func resetDetections() {
        captureQueue.async { [weak self] in
            self?.isInferring = false
            self?.roadServedSinceDriverCheck = true
            self?.driverWaitStarted = nil
            self?.clearBeltAlert = false
        }
        inferenceQueue.async { [weak self] in
            self?.trafficMonitor.reset()
            self?.followingMonitor.reset()
            self?.seatbeltMonitor.reset()
            self?.distractionMonitor.reset()
            self?.latchedSigns = []
            self?.latchedSignsAt = 0
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backDetections = []
            self.roadImageSize = .zero
            self.trafficStatus = .clear
            self.seatbeltUnbuckled = false
            self.distracted = false
        }
    }

    private func captureReportFrame(from sampleBuffer: CMSampleBuffer, isFront: Bool) {
        guard reportHandler != nil else { return }
        let now = CACurrentMediaTime()
        if isFront {
            guard !frontReportBusy, now - lastFrontReportTime >= frontSnapshotInterval else { return }
            frontReportBusy = true
            lastFrontReportTime = now
        } else {
            guard !backReportBusy, now - lastBackReportTime >= DriveRecorder.snapshotInterval else { return }
            backReportBusy = true
            lastBackReportTime = now
        }

        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let copy = copyPixelBuffer(source) else {
            if isFront { frontReportBusy = false } else { backReportBusy = false }
            return
        }

        let mirror = isFront
        let rotation = mirror ? previewRotationAngle : Self.backPreviewRotation(from: previewRotationAngle)
        let timestamp = Date()
        let handler = reportHandler
        reportQueue.async { [weak self] in
            let data = self?.reportJPEG(from: copy, mirror: mirror, rotation: rotation)
            if let data, let handler {
                handler(isFront, data, timestamp)
            }
            self?.captureQueue.async { [weak self] in
                guard let self else { return }
                if isFront {
                    self.frontReportBusy = false
                } else {
                    self.backReportBusy = false
                }
            }
        }
    }

    private func reportJPEG(from pixelBuffer: CVPixelBuffer, mirror: Bool, rotation: CGFloat) -> Data? {
        var image = orientedImage(from: pixelBuffer, mirror: mirror, rotation: rotation)
        let longest = max(image.extent.width, image.extent.height)
        let maxSide: CGFloat = 640
        if longest > maxSide, longest > 0 {
            let scale = maxSide / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            image = image.transformed(by: CGAffineTransform(
                translationX: -image.extent.origin.x,
                y: -image.extent.origin.y
            ))
        }
        guard let cgImage = reportCIContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.55)
    }

    private func jpegData(from sampleBuffer: CMSampleBuffer, mirror: Bool) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let rotation = mirror ? previewRotationAngle : Self.backPreviewRotation(from: previewRotationAngle)
        let image = orientedImage(from: pixelBuffer, mirror: mirror, rotation: rotation)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let data = ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: [:]) {
            return data
        }

        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }
}

extension DualCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let isFront = output === frontVideoOutput
        maybeDetect(from: sampleBuffer, isFront: isFront)
        captureReportFrame(from: sampleBuffer, isFront: isFront)

        guard awaitingPair else { return }

        guard let data = jpegData(from: sampleBuffer, mirror: isFront) else { return }

        if isFront {
            pendingFrontJPEG = data
        } else if output === backVideoOutput {
            pendingBackJPEG = data
        }

        finishPairIfReady()
    }
}

/// A setup failure while attaching a camera input, connection, or output. `DualCameraSession` surfaces the message when the session cannot start.
enum DualCameraError: LocalizedError {
    case cameraUnavailable(AVCaptureDevice.Position)
    case cannotAddInput(AVCaptureDevice.Position)
    case missingVideoPort(AVCaptureDevice.Position)
    case cannotAddConnection(AVCaptureDevice.Position)
    case cannotAddOutput(AVCaptureDevice.Position)
    case hardwareCostExceeded
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable(let position):
            return "No \(position.label) wide-angle camera was found."
        case .cannotAddInput(let position):
            return "Could not add the \(position.label) camera input."
        case .missingVideoPort(let position):
            return "Could not find a video port for the \(position.label) camera."
        case .cannotAddConnection(let position):
            return "Could not connect the \(position.label) camera."
        case .cannotAddOutput(let position):
            return "Could not add a capture output for the \(position.label) camera."
        case .hardwareCostExceeded:
            return "This device cannot run both cameras at the same time."
        case .imageEncodingFailed:
            return "Could not encode a captured image."
        }
    }
}

private extension AVCaptureDevice.Position {
    var label: String {
        switch self {
        case .front: return "front"
        case .back: return "back"
        default: return "unknown"
        }
    }
}
