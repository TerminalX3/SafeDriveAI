// The first-launch sequence: welcome, what the cameras watch, camera and location permission, and the driver profile.
// RootView shows it until onboarding is marked complete.
// The step views and fields in this file are used only by that flow.

import SwiftUI
import UIKit

/// The steps of first launch, from welcome through permissions and profile. `OnboardingFlowView` advances one step at a time.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case watches
    case camera
    case location
    case profile
    case ready

    var dot: Int? {
        switch self {
        case .welcome, .watches:
            return 0
        case .camera, .location, .profile:
            return 1
        case .ready:
            return nil
        }
    }

    var showsBack: Bool {
        switch self {
        case .welcome, .ready:
            return false
        default:
            return true
        }
    }

    var showsNext: Bool {
        switch self {
        case .welcome, .ready:
            return false
        default:
            return true
        }
    }
}

/// First-launch flow for permissions and the driver profile. `RootView` shows it until onboarding is marked complete.
struct OnboardingFlowView: View {
    @ObservedObject var store: OnboardingStore
    var onFinished: () -> Void

    @StateObject private var permissions = PermissionCenter()
    @State private var step: OnboardingStep = .welcome
    @State private var isRequesting = false
    @State private var didFinish = false
    @State private var profileAttempted = false

    var body: some View {
        ZStack {
            if step == .welcome || step == .ready {
                OnboardingFullBleed(name: "OnboardingWelcome")
            } else if step == .location {
                OnboardingFullBleed(name: "OnboardingMap", shiftX: 14)
            } else {
                VigilColor.canvas.ignoresSafeArea()
            }
            switch step {
            case .welcome:
                welcome
            case .watches:
                watches
            case .camera:
                cameraAccess
            case .location:
                locationAccess
            case .profile:
                profile
            case .ready:
                ready
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
                Spacer(minLength: 12)
                VigilMark(size: 78)
                VigilWordmark(size: 36)
                    .padding(.top, 8)
                Text("Drive aware. Arrive safer.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(VigilColor.navy)
                    .padding(.top, 6)
                Spacer(minLength: 16)
                Text("SafeDriveAI uses your phone’s cameras and location data to identify potentially unsafe driving behaviors and provide feedback after your drive.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(VigilColor.navy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
                VigilButton(title: "Get Started", showsArrow: true, action: advance)
                    .padding(.horizontal, 22)
                VigilPageDots(active: 0)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var watches: some View {
        stepScaffold {
            VStack(alignment: .leading, spacing: 8) {
                Text("What SafeDriveAI\nWatches")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("We analyze multiple factors to keep you safer on the road.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(VigilColor.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)

            VStack(spacing: 14) {
                WatchCard(
                    icon: "person.fill",
                    title: "Front Camera",
                    bullets: ["Seatbelt wear", "Driver attention"]
                )
                WatchCard(
                    icon: "road.lanes",
                    title: "Road Camera",
                    bullets: ["Traffic lights", "Stop signs", "Following distance", "Road conditions"]
                )
                WatchCard(
                    icon: "location.fill",
                    title: "GPS",
                    bullets: ["Speed", "Speed limit compliance", "Route information"]
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
    }

    private var cameraAccess: some View {
        permissionScaffold(
            icon: "camera.fill",
            title: "Camera Access",
            message: "SafeDriveAI needs camera access to analyze driver attention and road conditions while you’re driving.",
            allowTitle: "Allow Camera",
            allow: {
                guard !isRequesting else { return }
                isRequesting = true
                permissions.requestCamera {
                    isRequesting = false
                    advance()
                }
            }
        ) {
            VigilCard(radius: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    PermissionRow(icon: "person.fill.viewfinder", title: "Front camera", detail: "(driver monitoring)")
                    PermissionRow(icon: "video.fill", title: "Back camera", detail: "(road monitoring)")
                }
                .padding(16)
            }
            .padding(.horizontal, 22)
        }
    }

    private var locationAccess: some View {
        permissionScaffold(
            icon: "location.fill",
            title: "Location Access",
            message: "SafeDriveAI uses your location to estimate speed and identify applicable speed limits.",
            allowTitle: "Allow Location",
            backgroundName: "OnboardingMap",
            allow: {
                guard !isRequesting else { return }
                isRequesting = true
                permissions.requestLocation {
                    isRequesting = false
                    advance()
                }
            }
        ) {
            EmptyView()
        }
    }

    private var profile: some View {
        stepScaffold {
            VStack(spacing: 8) {
                VigilIconBadge(systemName: "person.fill", diameter: 76, iconSize: 30)
                Text("Your Driving Profile")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                    .multilineTextAlignment(.center)
                Text("This helps us personalize your reports and recommendations.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(VigilColor.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)

            ProfileFields(profile: $store.profile, showsEmailError: profileAttempted)
                .padding(.horizontal, 22)
                .padding(.top, 8)

            VigilButton(title: "Continue", action: saveAndAdvance)
                .padding(.horizontal, 22)
                .padding(.top, 8)
        }
    }

    private var ready: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                ZStack {
                    Circle()
                        .fill(VigilColor.iconWash)
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(VigilColor.blue)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("You’re all set!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                    .padding(.top, 18)
                Text("SafeDriveAI is ready to help you drive safer.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(VigilColor.navy)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            VigilButton(title: "Continue", showsArrow: true, action: finish)
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepScaffold<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                if step.showsBack {
                    VigilBackButton(action: goBack)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.bottom, 12)
            }
            VigilFooter(dot: step.dot, showsNext: step.showsNext, onNext: footerAdvance)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
        }
        .vigilScreenBackground()
    }

    private func permissionScaffold<Content: View>(
        icon: String,
        title: String,
        message: String,
        allowTitle: String,
        backgroundName: String? = nil,
        allow: @escaping () -> Void,
        @ViewBuilder extra: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VigilBackButton(action: goBack)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VigilIconBadge(systemName: icon)
                        .padding(.top, 12)
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(VigilColor.navy)
                    Text(message)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(VigilColor.body)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)
                    extra()
                }
                .frame(maxWidth: .infinity)
            }

            VigilButton(title: allowTitle, action: allow)
                .padding(.horizontal, 22)
                .disabled(isRequesting)
            VigilTextButton(title: "Not Now", action: advance)
            VigilFooter(dot: step.dot, showsNext: true, onNext: advance)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(OnboardingCanvasBackground(enabled: backgroundName == nil))
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            step = previous
        }
    }

    private func saveAndAdvance() {
        store.profile.email = store.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        store.profile.name = store.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.profile.age = store.profile.age.trimmingCharacters(in: .whitespacesAndNewlines)
        profileAttempted = true
        guard store.profile.isComplete else { return }
        store.saveProfile()
        advance()
    }

    private func footerAdvance() {
        if step == .profile {
            saveAndAdvance()
        } else {
            advance()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        store.completeOnboarding()
        onFinished()
    }
}

/// Full-screen onboarding image, shifted when the art should sit off center.
private struct OnboardingFullBleed: View {
    var name: String
    var shiftX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Image(name)
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .position(x: geo.size.width / 2 + shiftX, y: geo.size.height / 2)
        }
        .background(Color(red: 0.93, green: 0.96, blue: 0.99))
        .overlay(Color.white.opacity(0.42))
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Applies the pale canvas behind onboarding steps that are not full-bleed images.
private struct OnboardingCanvasBackground: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.vigilScreenBackground()
        } else {
            content
        }
    }
}

/// One card on the "what the app watches" onboarding step.
private struct WatchCard: View {
    let icon: String
    let title: String
    let bullets: [String]

    var body: some View {
        VigilCard(radius: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VigilColor.blue)
                    .frame(width: 40, height: 40)
                    .background(VigilColor.iconWash, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(VigilColor.navy)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(bullets, id: \.self) { bullet in
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(VigilColor.body.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                Text(bullet)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(VigilColor.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }
}

/// One camera or sensor row on the permission explanation step.
private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VigilColor.blue)
                .frame(width: 42, height: 42)
                .background(VigilColor.iconWash, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VigilColor.navy)
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(VigilColor.body)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Email, name, and age fields. Onboarding collects them, and the profile tab edits the saved values.
struct ProfileFields: View {
    @Binding var profile: DriverProfile
    var showsEmailError = false
    @FocusState private var focused: Field?

    /// Which profile field currently has the keyboard.
    private enum Field {
        case email
        case name
        case age
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                fieldCard(title: "Email", text: $profile.email, field: .email, keyboard: .emailAddress, contentType: .emailAddress)
                if showsEmailError, let message = profile.emailError {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VigilColor.danger)
                        .padding(.horizontal, 4)
                }
            }
            fieldCard(title: "Name", text: $profile.name, field: .name, keyboard: .default, contentType: .name)
            fieldCard(title: "Age", text: ageBinding, field: .age, keyboard: .numberPad, contentType: nil)
        }
    }

    private var ageBinding: Binding<String> {
        Binding(
            get: { profile.age },
            set: { newValue in
                profile.age = newValue.filter(\.isNumber)
            }
        )
    }

    private func fieldCard(
        title: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType,
        contentType: UITextContentType?
    ) -> some View {
        VigilCard(radius: 18) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VigilColor.body)
                    TextField(title, text: text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VigilColor.navy)
                        .keyboardType(keyboard)
                        .textContentType(contentType)
                        .textInputAutocapitalization(field == .email ? .never : .words)
                        .autocorrectionDisabled(field == .email)
                        .focused($focused, equals: field)
                        .submitLabel(field == .age ? .done : .next)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VigilColor.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { focused = field }
        }
    }
}
