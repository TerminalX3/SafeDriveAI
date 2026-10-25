// The app entry point.
// On launch it prepares the image folders and opens RootView, which chooses onboarding or home.
// AppDelegate reports the orientations OrientationLock currently allows.

import SwiftUI
import UIKit

/// Tells iOS which orientations are allowed. `SafeDriveAIApp` installs it, and it reports whatever `OrientationLock` last set.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// App entry point. It prepares the image folders, then opens `RootView`.
@main
struct SafeDriveAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        try? ImageStore.prepareDirectories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
