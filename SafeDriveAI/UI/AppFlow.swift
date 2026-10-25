// Switches the whole app between onboarding, home, the rotate prompt, and an active drive.
// RootView is the first view SafeDriveAIApp shows.
// OrientationLock changes when a drive starts in landscape and when the phone should return to portrait.

import SwiftUI
import UIKit

/// The orientations the app currently allows. `AppDelegate` reports `mask`, and `RootView` changes it when a drive starts or ends.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func apply(_ mask: UIInterfaceOrientationMask, prefer geometry: UIInterfaceOrientationMask? = nil) {
        self.mask = mask
        let work = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
                window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                if let geometry, !sceneAlreadyMatches(geometry, scene: scene) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: geometry)) { _ in }
                }
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func sceneAlreadyMatches(_ geometry: UIInterfaceOrientationMask, scene: UIWindowScene) -> Bool {
        switch scene.interfaceOrientation {
        case .landscapeLeft:
            return geometry.contains(.landscapeLeft)
        case .landscapeRight:
            return geometry.contains(.landscapeRight)
        case .portrait:
            return geometry.contains(.portrait)
        case .portraitUpsideDown:
            return geometry.contains(.portraitUpsideDown)
        default:
            return false
        }
    }
}

/// Which full-screen step `RootView` is showing: onboarding, home, a rotate prompt, or an active drive.
enum AppPhase: Equatable {
    case onboarding
    case home
    case awaitingLandscape
    case driving
    case awaitingPortrait
}

/// Top-level screen switcher. `SafeDriveAIApp` shows it, and it moves between onboarding, home, the rotate prompt, and the drive.
struct RootView: View {
    @StateObject private var store = OnboardingStore()
    @StateObject private var reports = DriveReportStore()
    @State private var phase: AppPhase
    @State private var finishedDriveID: UUID?

    init() {
        let completed = UserDefaults.standard.bool(forKey: OnboardingStore.completedKey)
        _phase = State(initialValue: completed ? .home : .onboarding)
    }

    var body: some View {
        ZStack {
            (phase == .driving ? Color.black : phase == .onboarding ? Color.clear : VigilColor.canvas)
                .ignoresSafeArea()
            switch phase {
            case .onboarding:
                OnboardingFlowView(store: store) {
                    showHome()
                }
            case .home:
                MainShell(
                    store: store,
                    reports: reports,
                    onStartDrive: beginDrive,
                    initialTab: finishedDriveID == nil ? .home : .reports,
                    focusDriveID: finishedDriveID
                )
            case .awaitingLandscape:
                RotatePromptView(target: .landscape, onCancel: showHome, onReady: startDrive)
            case .driving:
                ActiveDriveView(onEnd: endDrive)
            case .awaitingPortrait:
                RotatePromptView(
                    target: .portrait,
                    subtitle: "Turn your phone upright to open your drive report.",
                    statusText: "Your report opens once the phone is upright.",
                    onCancel: showFinishedDrive,
                    onReady: showFinishedDrive
                )
            }
        }
        .preferredColorScheme(phase == .driving ? .dark : .light)
        .tint(VigilColor.blue)
        .onAppear {
            if phase == .driving {
                OrientationLock.apply(.landscape, prefer: .landscape)
            } else if phase == .awaitingLandscape || phase == .awaitingPortrait {
                OrientationLock.apply(.allButUpsideDown)
            } else {
                OrientationLock.apply(.portrait, prefer: .portrait)
            }
        }
    }

    private func showHome() {
        OrientationLock.apply(.portrait, prefer: .portrait)
        phase = .home
    }

    private func beginDrive() {
        finishedDriveID = nil
        OrientationLock.apply(.allButUpsideDown)
        phase = .awaitingLandscape
    }

    private func startDrive() {
        OrientationLock.apply(.landscape, prefer: .landscape)
        phase = .driving
    }

    private func endDrive(_ report: DriveReport) {
        reports.add(report)
        finishedDriveID = report.id
        OrientationLock.apply(.allButUpsideDown)
        phase = .awaitingPortrait
    }

    private func showFinishedDrive() {
        OrientationLock.apply(.portrait, prefer: .portrait)
        phase = .home
    }
}

/// Asks the driver to turn the phone before a drive starts or after it ends. `RootView` shows it while waiting for landscape or portrait.
struct RotatePromptView: View {
    /// Whether this prompt is waiting for landscape, to start a drive, or portrait, to return home.
    enum Target {
        case landscape
        case portrait
    }

    var target: Target
    var subtitle: String? = nil
    var statusText: String? = nil
    var onCancel: () -> Void
    var onReady: () -> Void

    @State private var matched = false
    @State private var armed = false
    @State private var didAdvance = false
    @State private var settle: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VigilBackButton(action: cancel)
                Spacer()
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 12)
            VigilIconBadge(
                systemName: target == .landscape ? "iphone.landscape" : "iphone",
                diameter: 96,
                iconSize: 36
            )
            Text(target == .landscape ? "Switch to landscape" : "Switch to portrait")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(VigilColor.navy)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(subtitle ?? (target == .landscape
                 ? "Turn your phone sideways before your drive starts."
                 : "Turn your phone upright to return home."))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(VigilColor.body)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            PhoneRotateArt(towardLandscape: target == .landscape)
                .padding(.top, 28)

            Text(statusLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VigilColor.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 18)

            if target == .landscape {
                Text("Keep your eyes and hands on the road at all times, and drive carefully. SafeDriveAI works best in good lighting and clear weather.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VigilColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            }

            Spacer()

            if target == .landscape && matched {
                VigilButton(title: "Start Drive", showsArrow: true, action: advance)
                    .padding(.horizontal, 22)
            }
            VigilTextButton(title: "Not Now", action: cancel)
                .padding(.bottom, 12)
        }
        .vigilScreenBackground()
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        noteSize(geo.size)
                    }
                    .onChange(of: geo.size) { _, size in
                        noteSize(size)
                    }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            armed = true
            if target == .portrait && !matched {
                advance()
            } else if target == .landscape && matched {
                scheduleAdvance()
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .onDisappear {
            settle?.cancel()
        }
    }

    private func noteSize(_ size: CGSize) {
        let isLandscape = size.width > size.height + 48
        matched = isLandscape
        let ready = target == .landscape ? isLandscape : !isLandscape
        guard armed, ready else {
            settle?.cancel()
            return
        }
        scheduleAdvance()
    }

    private func scheduleAdvance() {
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private var statusLine: String {
        switch target {
        case .landscape:
            return matched
                ? "Your phone is sideways. Start when you’re ready."
                : "Your drive starts once the phone is landscape."
        case .portrait:
            return statusText ?? "Home opens once the phone is upright."
        }
    }

    private func advance() {
        guard !didAdvance else { return }
        didAdvance = true
        onReady()
    }

    private func cancel() {
        guard !didAdvance else { return }
        didAdvance = true
        onCancel()
    }
}

/// Owns the camera, speed, and recorder for one drive, and shows `ContentView`. `RootView` presents it once the phone is landscape.
struct ActiveDriveView: View {
    var onEnd: (DriveReport) -> Void

    @StateObject private var camera = DualCameraSession()
    @StateObject private var speedMonitor = SpeedMonitor()
    @StateObject private var recorder = DriveRecorder()
    @State private var didEnd = false

    var body: some View {
        ContentView(camera: camera, speedMonitor: speedMonitor, recorder: recorder)
            .overlay(alignment: .topLeading) {
                Button(action: end) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("End Drive")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(VigilColor.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
                .padding(.leading, 44)
                .accessibilityLabel("End drive")
            }
            .ignoresSafeArea()
    }

    private func end() {
        guard !didEnd else { return }
        didEnd = true
        onEnd(recorder.finish(camera: camera))
    }
}
