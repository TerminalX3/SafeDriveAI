// Saves the driver profile and whether onboarding has been finished, using UserDefaults on this phone.
// PermissionCenter asks for camera and location access from the permission steps.
// RootView reads the store to decide whether to open onboarding or home.

import AVFoundation
import CoreLocation
import Foundation

/// The driver's name, email, and age, saved on this phone. `OnboardingStore` reads and writes it.
struct DriverProfile: Codable, Equatable {
    var email: String
    var name: String
    var age: String

    static let empty = DriverProfile(email: "", name: "", age: "")

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
    }

    var isComplete: Bool {
        Self.isValidEmail(email)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var emailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Enter your email address."
        }
        if !Self.isValidEmail(trimmed) {
            return "Enter a valid email address."
        }
        return nil
    }

    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 254, !trimmed.contains(" ") else { return false }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

@MainActor
/// Saves the driver profile and whether onboarding is finished. `RootView` uses it to choose the first screen.
final class OnboardingStore: ObservableObject {
    @Published var profile: DriverProfile
    @Published private(set) var hasCompletedOnboarding: Bool

    static let completedKey = "vigildrive.onboardingComplete"

    private let defaults: UserDefaults
    private let profileKey = "vigildrive.driverProfile.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: profileKey),
           let saved = try? JSONDecoder().decode(DriverProfile.self, from: data) {
            profile = saved
        } else {
            profile = .empty
        }
        hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
    }

    /// Writes the driving profile on this phone. Called once, from the profile step.
    func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }

    func completeOnboarding() {
        saveProfile()
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
    }
}

@MainActor
/// Asks for camera and location access during onboarding. `OnboardingFlowView` calls it from the permission steps.
final class PermissionCenter: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationCompletion: (() -> Void)?

    func requestCamera(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { completion() }
            }
        default:
            completion()
        }
    }

    func requestLocation(completion: @escaping () -> Void) {
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationCompletion = completion
            locationManager.requestWhenInUseAuthorization()
        } else {
            completion()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor in
            let finish = locationCompletion
            locationCompletion = nil
            finish?()
        }
    }
}
