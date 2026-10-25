// The reports tab and the screen for one saved drive.
// The list opens a detail view with scores, a speed map, and violation clips.
// From there the driver can email a PDF or hand it to the system share sheet.

import MapKit
import MessageUI
import SwiftUI
import UIKit

/// List of saved drives. `MainShell` shows it on the reports tab.
struct ReportsView: View {
    var reports: [DriveReport]
    @Binding var openReportID: UUID?
    var recipientEmail: String
    var onDelete: (UUID) -> Void

    @State private var pendingDelete: DriveReport?

    private var recent: [DriveReport] {
        Array(reports.prefix(7).reversed())
    }

    var body: some View {
        Group {
            if let openReportID, let report = reports.first(where: { $0.id == openReportID }) {
                DriveDetailView(report: report, recipientEmail: recipientEmail, onBack: {
                    self.openReportID = nil
                }, onDelete: {
                    pendingDelete = report
                })
            } else {
                list
            }
        }
        .confirmationDialog(
            "Delete this drive?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Drive", role: .destructive) {
                if let drive = pendingDelete {
                    if openReportID == drive.id {
                        openReportID = nil
                    }
                    onDelete(drive.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes the score, clips, and speed map for this drive.")
        }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reports")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                    .padding(.top, 8)
                VigilCard(radius: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("RECENT DRIVES")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.7)
                        }
                        .foregroundStyle(VigilColor.muted)
                        WeeklyTrendChart(
                            scores: recent.map(\.overall),
                            days: recent.map { $0.endedAt.formatted(.dateTime.weekday(.abbreviated)) }
                        )
                    }
                    .padding(16)
                }

                Text("Drives")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(VigilColor.navy)
                    .padding(.top, 4)

                if reports.isEmpty {
                    VigilCard(radius: 18) {
                        Text("Finish a drive to generate a safety report.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VigilColor.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    ForEach(reports) { drive in
                        VigilCard(radius: 18) {
                            HStack(spacing: 12) {
                                Button {
                                    openReportID = drive.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(DriveReportFormat.score(drive.overall))
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(scoreColor(drive.overall))
                                            .frame(width: 52, height: 48)
                                            .background(VigilColor.iconWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(DriveReportFormat.title(for: drive.endedAt))
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(VigilColor.navy)
                                            Text("\(DriveReportFormat.miles(drive.distanceMeters)) · \(DriveReportFormat.duration(drive.duration))")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(VigilColor.body)
                                        }
                                        Spacer(minLength: 8)
                                        Text("\(DriveReportFormat.score(drive.overall))/10")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(VigilColor.muted)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(VigilColor.muted)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button {
                                    pendingDelete = drive
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(VigilColor.danger)
                                        .frame(width: 36, height: 36)
                                        .background(VigilColor.danger.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(DriveReportFormat.title(for: drive.endedAt))")
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// Scores, map, and clips for one saved drive. `ReportsView` pushes it when a drive is opened.
struct DriveDetailView: View {
    var report: DriveReport
    var recipientEmail: String
    var onBack: () -> Void
    var onDelete: () -> Void

    @State private var expanded: Set<ReportSection> = []
    @State private var isExporting = false
    @State private var isMailing = false
    @State private var exportFile: ReportExportFile?
    @State private var mailDraft: ReportMailDraft?
    @State private var mailAlert: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VigilBackButton(action: onBack)
                    Spacer()
                }
                HStack(alignment: .center, spacing: 10) {
                    Text("Drive Report")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(VigilColor.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 12)
                    Button {
                        Task { await exportReport() }
                    } label: {
                        headerIcon(
                            isExporting ? "progress" : "square.and.arrow.up",
                            tint: VigilColor.blue,
                            wash: VigilColor.iconWash
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel("Export drive report")
                    Button(action: onDelete) {
                        headerIcon("trash", tint: VigilColor.danger, wash: VigilColor.danger.opacity(0.12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete this drive")
                    .accessibilityHint("Asks you to confirm before deleting")
                    Button {
                        Task { await mailReport() }
                    } label: {
                        headerIcon(
                            isMailing ? "progress" : "envelope.fill",
                            tint: VigilColor.blue,
                            wash: VigilColor.iconWash
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel("Email this report")
                }
                scoreCard
                routeCard
                ForEach(ReportSection.allCases) { section in
                    sectionCard(section)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .sheet(item: $exportFile) { file in
            ReportShareSheet(url: file.url)
                .ignoresSafeArea()
        }
        .sheet(item: $mailDraft) { draft in
            ReportMailComposer(draft: draft) {
                mailDraft = nil
            }
            .ignoresSafeArea()
        }
        .alert("Can't send mail", isPresented: Binding(
            get: { mailAlert != nil },
            set: { if !$0 { mailAlert = nil } }
        )) {
            Button("OK", role: .cancel) { mailAlert = nil }
        } message: {
            Text(mailAlert ?? "")
        }
        .onAppear {
            var open = Set<ReportSection>()
            for section in ReportSection.allCases {
                if section == .speedLimit {
                    if !report.track.isEmpty {
                        open.insert(section)
                    }
                } else if !report.clips(for: section).isEmpty {
                    open.insert(section)
                }
            }
            expanded = open
        }
    }

    private var scoreCard: some View {
        VigilCard(radius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(DriveReportFormat.title(for: report.endedAt))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VigilColor.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DriveReportFormat.score(report.overall))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(scoreColor(report.overall))
                    Text("/10")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(VigilColor.muted)
                }
                Text("Safety Score")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VigilColor.navy)
                Text("\(DriveReportFormat.miles(report.distanceMeters)) · \(DriveReportFormat.duration(report.duration))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VigilColor.body)
                if let caption = report.overallCaption {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VigilColor.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var routeCard: some View {
        VigilCard(radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                if report.track.isEmpty, violationPins.isEmpty {
                    Text(ReportSection.speedLimit.emptyDetail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VigilColor.body)
                } else {
                    SpeedTrackMap(track: report.track, pins: violationPins)
                    HStack(spacing: 14) {
                        legendDot(color: VigilColor.green, title: "Under")
                        legendDot(color: VigilColor.danger, title: "Over")
                        legendDot(color: VigilColor.trackGrey, title: "No limit")
                        legendDot(color: VigilColor.pin, title: "Violation")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var violationPins: [MapViolationPin] {
        report.clips.compactMap { clip in
            guard let latitude = clip.latitude, let longitude = clip.longitude else { return nil }
            return MapViolationPin(
                id: clip.id,
                latitude: latitude,
                longitude: longitude,
                title: clip.section.title
            )
        }
    }

    private var isBusy: Bool { isExporting || isMailing }

    private func exportReport() async {
        guard !isBusy else { return }
        isExporting = true
        let url = await DriveReportPDF.write(report)
        isExporting = false
        if let url {
            exportFile = ReportExportFile(url: url)
        }
    }

    private func mailReport() async {
        guard !isBusy else { return }
        let address = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DriverProfile.isValidEmail(address) else {
            mailAlert = "Add an email address in Profile before sending a report."
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            mailAlert = "Set up the Mail app on this iPhone to send the report."
            return
        }
        isMailing = true
        let url = await DriveReportPDF.write(report)
        let data = url.flatMap { try? Data(contentsOf: $0) }
        isMailing = false
        guard let data else {
            mailAlert = "The report could not be prepared."
            return
        }
        mailDraft = ReportMailDraft(
            recipient: address,
            subject: "SafeDriveAI report · \(DriveReportFormat.title(for: report.endedAt))",
            body: mailBody,
            attachment: data
        )
    }

    private var mailBody: String {
        var lines = [
            "Here is your SafeDriveAI report for \(DriveReportFormat.title(for: report.endedAt)).",
            "",
            "Safety score: \(DriveReportFormat.score(report.overall))/10",
            "\(DriveReportFormat.miles(report.distanceMeters)) · \(DriveReportFormat.duration(report.duration))",
            ""
        ]
        for section in ReportSection.allCases {
            let score = report.score(for: section).map { "\(DriveReportFormat.score($0))/10" } ?? "—"
            lines.append("\(section.title): \(score) · \(report.subtitle(for: section))")
        }
        lines.append("")
        lines.append("The one-page map and scores are attached.")
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func headerIcon(_ symbol: String, tint: Color, wash: Color) -> some View {
        Group {
            if symbol == "progress" {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(wash, in: Circle())
    }

    private func sectionCard(_ section: ReportSection) -> some View {
        let isOpen = expanded.contains(section)
        return VigilCard(radius: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isOpen {
                            expanded.remove(section)
                        } else {
                            expanded.insert(section)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(VigilColor.blue)
                            .frame(width: 40, height: 40)
                            .background(VigilColor.iconWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(VigilColor.navy)
                            Text(report.subtitle(for: section))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(VigilColor.body)
                        }
                        Spacer(minLength: 8)
                        Text(scoreLabel(for: section))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(sectionScoreColor(section))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(VigilColor.muted)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title), \(scoreLabel(for: section))")
                .accessibilityHint(isOpen ? "Collapses details" : "Shows details")

                if isOpen {
                    Divider().overlay(VigilColor.line)
                    sectionBody(section)
                        .padding(14)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: ReportSection) -> some View {
        switch section {
        case .speedLimit:
            speedBody
        case .stopSign, .trafficLight, .following, .seatbelt, .distracted:
            clipBody(section)
        }
    }

    private func clipBody(_ section: ReportSection) -> some View {
        let clips = report.clips(for: section)
        return VStack(alignment: .leading, spacing: 14) {
            if clips.isEmpty {
                Text(section.emptyDetail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VigilColor.body)
            } else {
                ForEach(clips) { clip in
                    ViolationClipPlayer(driveID: report.id, clip: clip, interval: report.clipFrameInterval)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(speedSummary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VigilColor.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedSummary: String {
        guard report.speedScore != nil else {
            return "This score stays out of the average until a posted limit is available."
        }
        if report.overLimitSeconds == 0 {
            return "You stayed within the limit while moving and a limit was known."
        }
        let over = DriveReportFormat.duration(TimeInterval(report.overLimitSeconds))
        let known = DriveReportFormat.duration(TimeInterval(report.knownMovingSeconds))
        return "Over the limit for \(over) of \(known) while moving."
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VigilColor.body)
        }
    }

    private func scoreLabel(for section: ReportSection) -> String {
        guard let value = report.score(for: section) else { return "—" }
        return "\(DriveReportFormat.score(value))/10"
    }

    private func sectionScoreColor(_ section: ReportSection) -> Color {
        guard let value = report.score(for: section) else { return VigilColor.muted }
        return scoreColor(value)
    }
}

/// Plays the saved frames of one violation clip on the drive detail screen.
struct ViolationClipPlayer: View {
    var driveID: UUID
    var clip: ViolationClip
    var interval: TimeInterval

    @State private var fronts: [UIImage?] = []
    @State private var backs: [UIImage?] = []
    @State private var index = 0
    @State private var playing = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DriveReportFormat.clock(clip.startedAt))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VigilColor.muted)
                Spacer()
                Text(clipProgress)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VigilColor.muted)
            }
            if clip.frameCount == 0 {
                Text("No camera frames were saved for this moment.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VigilColor.body)
            } else {
                film
                    .onTapGesture(perform: togglePlay)
                progressBar
                HStack(spacing: 8) {
                    clipControl(playSymbol, label: playing ? "Pause clip" : "Play clip", action: togglePlay)
                    Spacer()
                    clipControl("arrow.up.left.and.arrow.down.right", label: "Expand clip") {
                        expanded = true
                    }
                }
            }
            Text(clip.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VigilColor.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fullScreenCover(isPresented: $expanded) {
            expandedClip
        }
        .task {
            let loaded = loadFrames()
            fronts = loaded.front
            backs = loaded.back
        }
        .task(id: playing) {
            guard playing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(interval, 0.05)))
                if Task.isCancelled { return }
                if index >= clip.frameCount - 1 {
                    playing = false
                    return
                }
                index += 1
            }
        }
    }

    private var expandedClip: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button {
                        expanded = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close clip")
                    Spacer()
                    Text(clipProgress)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button(action: togglePlay) {
                        Image(systemName: playSymbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Pause clip" : "Play clip")
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
                Group {
                    if let primaryFrame {
                        Image(uiImage: primaryFrame)
                            .resizable()
                            .scaledToFit()
                    } else {
                        VigilColor.navy.opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: togglePlay)
                Spacer(minLength: 0)
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    private func clipControl(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(VigilColor.navy)
                .frame(width: 36, height: 36)
                .background(VigilColor.iconWash, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var film: some View {
        frameBox(image: primaryFrame, title: clip.section.savesRoad ? "Road" : "Driver", height: 220)
    }

    private func frameBox(image: UIImage?, title: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    VigilColor.navy.opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(VigilColor.line)
                Capsule()
                    .fill(VigilColor.blue)
                    .frame(width: max(8, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Clip progress")
    }

    private var primaryFrame: UIImage? {
        let frames = clip.section.savesRoad ? backs : fronts
        guard frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    private var progress: Double {
        guard clip.frameCount > 1 else { return 1 }
        return Double(index) / Double(clip.frameCount - 1)
    }

    private var clipProgress: String {
        let elapsed = Double(index) * interval
        return String(format: "0:%02.0f", elapsed.rounded())
    }

    private var playSymbol: String {
        if playing { return "pause.fill" }
        if index >= max(clip.frameCount - 1, 0), index > 0 { return "arrow.clockwise" }
        return "play.fill"
    }

    private func togglePlay() {
        if index >= max(clip.frameCount - 1, 0) {
            index = 0
        }
        playing.toggle()
    }

    private func loadFrames() -> (front: [UIImage?], back: [UIImage?]) {
        let directory = DriveReportArchive.clipDirectory(drive: driveID, clip: clip.id)
        var front: [UIImage?] = []
        var back: [UIImage?] = []
        let road = clip.section.savesRoad
        for frame in 0..<clip.frameCount {
            let name = String(format: "%03d.jpg", frame)
            if road {
                front.append(nil)
                back.append(UIImage(contentsOfFile: directory.appendingPathComponent("back-\(name)").path))
            } else {
                front.append(UIImage(contentsOfFile: directory.appendingPathComponent("front-\(name)").path))
                back.append(nil)
            }
        }
        return (front, back)
    }
}

/// A map pin for one violation that has a saved location. `SpeedTrackMap` places these on the drive route.
struct MapViolationPin: Identifiable, Equatable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var title: String
}

/// A temporary PDF URL handed to the system share sheet from the drive detail screen.
struct ReportExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Recipient, subject, body, and PDF attachment for emailing one drive report.
struct ReportMailDraft: Identifiable {
    let id = UUID()
    var recipient: String
    var subject: String
    var body: String
    var attachment: Data
}

/// Presents the system mail composer for a `ReportMailDraft`. The drive detail screen shows it when the driver emails a report.
struct ReportMailComposer: UIViewControllerRepresentable {
    var draft: ReportMailDraft
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([draft.recipient])
        mail.setSubject(draft.subject)
        mail.setMessageBody(draft.body, isHTML: false)
        mail.addAttachmentData(draft.attachment, mimeType: "application/pdf", fileName: "SafeDriveAI-Report.pdf")
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    /// Dismisses the mail composer when the driver sends or cancels.
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}

/// System share sheet for a report PDF. The drive detail screen presents it when mail is unavailable.
struct ReportShareSheet: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Map of one drive's speed track, colored by `SpeedBand`, with pins for violations. The drive detail screen shows it.
struct SpeedTrackMap: View {
    var track: [SpeedTrackPoint]
    var pins: [MapViolationPin] = []

    var body: some View {
        Map(initialPosition: .region(region)) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.points.count >= 2 {
                    MapPolyline(coordinates: coordinates(segment.points))
                        .stroke(color(for: segment.band), lineWidth: 6)
                }
            }
            if showsSinglePoint, let first = track.first {
                Annotation("Location", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                    Circle()
                        .fill(color(for: first.band))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(VigilColor.pin)
                        .background(Circle().fill(.white).frame(width: 10, height: 10))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipped()
        .accessibilityLabel("Map of this drive. Green is under the speed limit, red is over, grey is an unknown limit, and yellow pins mark violations.")
    }

    private var segments: [SpeedMapSegment] {
        DriveScore.mapSegments(from: track)
    }

    private var showsSinglePoint: Bool {
        track.count == 1 || segments.allSatisfy { $0.points.count < 2 }
    }

    private var region: MKCoordinateRegion {
        let latitudes = track.map(\.latitude) + pins.map(\.latitude)
        let longitudes = track.map(\.longitude) + pins.map(\.longitude)
        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else {
            return MKCoordinateRegion()
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.02, (maxLat - minLat) * 3.2),
                longitudeDelta: max(0.02, (maxLon - minLon) * 3.2)
            )
        )
    }

    private func coordinates(_ points: [GeoPoint]) -> [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func color(for band: SpeedBand) -> Color {
        switch band {
        case .under: return VigilColor.green
        case .over: return VigilColor.danger
        case .unknown: return VigilColor.trackGrey
        }
    }
}

func scoreColor(_ score: Double) -> Color {
    if score >= 8 { return VigilColor.green }
    if score >= 6 { return VigilColor.amberInk }
    return VigilColor.danger
}
