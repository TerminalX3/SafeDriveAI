// The shared visual kit: colors, the logo, buttons, page dots, icon badges, and cards.
// Onboarding, home, reports, and the rotate prompt use these instead of one-off styles.

import SwiftUI

/// Shared colors for screens, cards, and charts. Views across onboarding, home, and reports read these instead of hard-coded values.
enum VigilColor {
    static let blue = Color(red: 91 / 255, green: 148 / 255, blue: 255 / 255)
    static let blueDeep = Color(red: 55 / 255, green: 112 / 255, blue: 242 / 255)
    static let blueSoft = Color(red: 126 / 255, green: 176 / 255, blue: 255 / 255)
    static let navy = Color(red: 31 / 255, green: 45 / 255, blue: 72 / 255)
    static let body = Color(red: 125 / 255, green: 136 / 255, blue: 158 / 255)
    static let muted = Color(red: 158 / 255, green: 170 / 255, blue: 188 / 255)
    static let canvas = Color(red: 245 / 255, green: 250 / 255, blue: 253 / 255)
    static let line = Color(red: 226 / 255, green: 234 / 255, blue: 242 / 255)
    static let iconWash = Color(red: 232 / 255, green: 242 / 255, blue: 255 / 255)
    static let dot = Color(red: 214 / 255, green: 224 / 255, blue: 236 / 255)
    static let green = Color(red: 39 / 255, green: 164 / 255, blue: 112 / 255)
    static let greenWash = Color(red: 230 / 255, green: 247 / 255, blue: 237 / 255)
    static let danger = Color(red: 214 / 255, green: 72 / 255, blue: 78 / 255)
    static let trackGrey = Color(red: 158 / 255, green: 168 / 255, blue: 180 / 255)
    static let amber = Color(red: 255 / 255, green: 243 / 255, blue: 220 / 255)
    static let amberInk = Color(red: 184 / 255, green: 128 / 255, blue: 42 / 255)
    static let pin = Color(red: 242 / 255, green: 184 / 255, blue: 28 / 255)
    static let purple = Color(red: 124 / 255, green: 108 / 255, blue: 224 / 255)
    static let orange = Color(red: 242 / 255, green: 153 / 255, blue: 74 / 255)
    static let shadow = Color(red: 28 / 255, green: 52 / 255, blue: 90 / 255)
}

/// The app logo image. Onboarding and the home header show it beside the wordmark.
struct VigilMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("VigilLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The "Vigil" wordmark image. It sits next to `VigilMark` on the welcome and home screens.
struct VigilWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Text("SafeDrive")
                .foregroundStyle(VigilColor.navy)
            Text("AI")
                .foregroundStyle(VigilColor.blue)
        }
        .font(.system(size: size, weight: .bold))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SafeDriveAI")
    }
}

/// Primary filled button used to continue onboarding and start a drive.
struct VigilButton: View {
    let title: String
    var showsArrow = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if showsArrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(VigilColor.blue, in: Capsule())
            .shadow(color: VigilColor.blue.opacity(0.28), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// Secondary text button, such as "Not Now" on the permission and rotate screens.
struct VigilTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(VigilColor.body)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .buttonStyle(.plain)
    }
}

/// Circular next control in the onboarding footer. `VigilFooter` shows it on steps that can advance.
struct VigilNextButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(VigilColor.blue, in: Circle())
                .shadow(color: VigilColor.blue.opacity(0.28), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next")
    }
}

/// Back control for onboarding steps and the drive detail screen.
struct VigilBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VigilColor.navy)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// Page dots for the onboarding steps. `VigilFooter` highlights the current one.
struct VigilPageDots: View {
    var active: Int
    var count = 4

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == active ? VigilColor.blue : VigilColor.dot)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(active + 1) of \(count)")
    }
}

/// Bottom bar of an onboarding step, with page dots and an optional next button.
struct VigilFooter: View {
    var dot: Int?
    var showsNext: Bool
    var onNext: () -> Void

    var body: some View {
        ZStack {
            if let dot {
                VigilPageDots(active: dot)
            }
            if showsNext {
                HStack {
                    Spacer()
                    VigilNextButton(action: onNext)
                }
            }
        }
        .frame(height: 56)
    }
}

/// Circular icon used on permission, profile, and rotate screens.
struct VigilIconBadge: View {
    let systemName: String
    var diameter: CGFloat = 92
    var iconSize: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(VigilColor.blue)
            .frame(width: diameter, height: diameter)
            .background(VigilColor.iconWash, in: Circle())
    }
}

/// Rounded white card used for lists, scores, and profile fields.
struct VigilCard<Content: View>: View {
    var radius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(VigilColor.line, lineWidth: 1)
            )
            .shadow(color: VigilColor.shadow.opacity(0.05), radius: 16, y: 8)
    }
}

extension View {
    func vigilScreenBackground() -> some View {
        background(
            LinearGradient(
                colors: [
                    Color(red: 232 / 255, green: 244 / 255, blue: 252 / 255),
                    VigilColor.canvas,
                    VigilColor.canvas
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
