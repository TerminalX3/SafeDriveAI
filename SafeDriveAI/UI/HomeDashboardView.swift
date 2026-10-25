// The tabbed home after onboarding.
// The home tab lists recent drives and starts a new one, the reports tab opens saved drives, and the profile tab shows the driver and practice hours.
// RootView shows this shell whenever the app is not in a drive.

import SwiftUI

/// Home, reports, and profile tabs. `MainShell` switches among them.
enum VigilTab: String, CaseIterable, Identifiable {
    case home
    case reports
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .reports: return "Reports"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .reports: return "doc.text.fill"
        case .profile: return "person.fill"
        }
    }
}

/// Tab shell after onboarding. `RootView` shows it, and starting a drive leaves this screen for the rotate prompt.
struct MainShell: View {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var reports: DriveReportStore
    var onStartDrive: () -> Void

    @State private var tab: VigilTab
    @State private var openReportID: UUID?

    init(
        store: OnboardingStore,
        reports: DriveReportStore,
        onStartDrive: @escaping () -> Void,
        initialTab: VigilTab = .home,
        focusDriveID: UUID? = nil
    ) {
        self.store = store
        self.reports = reports
        self.onStartDrive = onStartDrive
        _tab = State(initialValue: initialTab)
        _openReportID = State(initialValue: focusDriveID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:
                    HomeDashboard(
                        name: store.profile.displayName,
                        reports: reports.reports,
                        onStartDrive: onStartDrive,
                        openTab: { tab = $0 },
                        showReport: { id in
                            openReportID = id
                            tab = .reports
                        }
                    )
                case .reports:
                    ReportsView(
                        reports: reports.reports,
                        openReportID: $openReportID,
                        recipientEmail: store.profile.email,
                        onDelete: { reports.delete($0) }
                    )
                case .profile:
                    SavedProfileView(store: store, reports: reports.reports)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VigilTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
        }
        .vigilScreenBackground()
    }
}

/// Home tab: recent drives, the weekly chart, and the button that starts a drive.
struct HomeDashboard: View {
    var name: String
    var reports: [DriveReport]
    var onStartDrive: () -> Void
    var openTab: (VigilTab) -> Void
    var showReport: (UUID?) -> Void

    private var latest: DriveReport? { reports.first }

    private var recent: [DriveReport] {
        Array(reports.prefix(7).reversed())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                greetingBlock
                startButton
                lastDriveCard
                trendCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VigilMark(size: 40)
            VStack(alignment: .leading, spacing: 0) {
                VigilWordmark(size: 24)
                Text("Drive aware. Arrive safer.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VigilColor.body)
            }
            Spacer(minLength: 8)
            Button {
                openTab(.profile)
            } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VigilColor.navy.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.8), in: Circle())
                    .overlay(Circle().stroke(VigilColor.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(VigilColor.navy)
            Text(name)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(VigilColor.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        Button(action: onStartDrive) {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: "steeringwheel")
                        .font(.system(size: 18, weight: .semibold))
                    Text("START DRIVE")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(0.8)
                }
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(VigilColor.blue, in: Capsule())
            .shadow(color: VigilColor.blue.opacity(0.28), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start drive")
    }

    @ViewBuilder
    private var lastDriveCard: some View {
        if let latest {
            VigilCard(radius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text("LAST DRIVE")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                    }
                    .foregroundStyle(VigilColor.muted)

                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(scoreColor(latest.overall))
                                    .frame(width: 44, height: 44)
                                    .background(VigilColor.greenWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(DriveReportFormat.score(latest.overall))
                                            .font(.system(size: 34, weight: .bold))
                                            .foregroundStyle(VigilColor.navy)
                                        Text("/10")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(VigilColor.muted)
                                    }
                                    Text("Safety Score")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(VigilColor.body)
                                }
                            }
                            previousDelta
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle()
                            .fill(VigilColor.line)
                            .frame(width: 1)
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 12) {
                            statLine(icon: "road.lanes", value: DriveReportFormat.miles(latest.distanceMeters), caption: "Distance")
                            statLine(icon: "clock", value: DriveReportFormat.duration(latest.duration), caption: "Duration")
                            improveButton(for: latest)
                        }
                        .padding(.leading, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        } else {
            VigilCard(radius: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text("LAST DRIVE")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                    }
                    .foregroundStyle(VigilColor.muted)
                    Text("Your safety score shows up here after your first drive.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VigilColor.body)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var previousDelta: some View {
        if reports.count >= 2, let latest {
            let delta = latest.overall - reports[1].overall
            if abs(delta) < 0.05 {
                Text("Same as your previous drive")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VigilColor.body)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(String(format: "%+.1f", delta))
                        .font(.system(size: 13, weight: .bold))
                    Text("vs. previous drive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VigilColor.body)
                }
                .foregroundStyle(delta > 0 ? VigilColor.green : VigilColor.danger)
            }
        }
    }

    private func improveButton(for report: DriveReport) -> some View {
        let weak = report.weakSections
        return Button {
            showReport(report.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: weak.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(weak.isEmpty ? "No issues flagged" : "\(weak.count) area\(weak.count == 1 ? "" : "s") to improve")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(weak.isEmpty ? VigilColor.green : VigilColor.amberInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(weak.isEmpty ? VigilColor.greenWash : VigilColor.amber, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statLine(icon: String, value: String, caption: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VigilColor.muted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VigilColor.body)
            }
        }
    }

    private var trendCard: some View {
        VigilCard(radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("WEEKLY TREND")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                    }
                    .foregroundStyle(VigilColor.muted)
                    Spacer()
                    Button {
                        showReport(nil)
                    } label: {
                        HStack(spacing: 2) {
                            Text("View details")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VigilColor.blue)
                    }
                    .buttonStyle(.plain)
                }
                WeeklyTrendChart(
                    scores: recent.map(\.overall),
                    days: recent.map { $0.endedAt.formatted(.dateTime.weekday(.abbreviated)) }
                )
            }
            .padding(16)
        }
    }
}

/// Profile tab showing the saved driver fields and practice-hour progress.
struct SavedProfileView: View {
    @ObservedObject var store: OnboardingStore
    var reports: [DriveReport]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    VigilIconBadge(systemName: "person.fill", diameter: 76, iconSize: 30)
                        .padding(.top, 8)
                    Text("Your Driving Profile")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(VigilColor.navy)
                    Text("This helps us personalize your reports and recommendations.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(VigilColor.body)
                        .multilineTextAlignment(.center)
                }
                PracticeHoursCard()
                ProfileFields(profile: $store.profile)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .onChange(of: store.profile) { _, _ in
            store.saveProfile()
        }
    }
}

/// Progress toward New Jersey's 50 supervised hours, including the 10 hours after dark. The profile tab shows it.
struct PracticeHoursCard: View {
    private var totalHours: Double {
        PracticeHours.loggedHours
    }

    private var nightHours: Double {
        PracticeHours.loggedNightHours
    }

    var body: some View {
        VigilCard(radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("PRACTICE HOURS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                }
                .foregroundStyle(VigilColor.muted)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hourText(totalHours))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(totalHours >= PracticeHours.requiredHours ? VigilColor.green : VigilColor.navy)
                    Text("/ \(Int(PracticeHours.requiredHours)) hours")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VigilColor.muted)
                }

                ProgressView(value: min(totalHours / PracticeHours.requiredHours, 1))
                    .tint(totalHours >= PracticeHours.requiredHours ? VigilColor.green : VigilColor.blue)

                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VigilColor.blueDeep)
                    Text("\(hourText(nightHours)) / \(Int(PracticeHours.requiredNightHours)) hours after dark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VigilColor.navy)
                }

                Text(statusLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VigilColor.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Practice hours \(hourText(totalHours)) of \(Int(PracticeHours.requiredHours)), including \(hourText(nightHours)) of \(Int(PracticeHours.requiredNightHours)) after dark")
    }

    private var statusLine: String {
        if totalHours >= PracticeHours.requiredHours, nightHours >= PracticeHours.requiredNightHours {
            return "Both New Jersey practice requirements are met."
        }
        return "New Jersey requires 50 supervised hours before a probationary license, including 10 after dark."
    }

    private func hourText(_ hours: Double) -> String {
        String(format: "%.1f", hours)
    }
}

/// Bottom bar for the home, reports, and profile tabs. `MainShell` binds the selection.
struct VigilTabBar: View {
    @Binding var selection: VigilTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(VigilTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? VigilColor.blue : VigilColor.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(VigilColor.iconWash)
                                .padding(.horizontal, 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(VigilColor.line, lineWidth: 1)
        )
        .shadow(color: VigilColor.shadow.opacity(0.08), radius: 16, y: 6)
    }
}
