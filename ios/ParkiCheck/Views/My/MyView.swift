import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var intakes: [MedicationEntry]
    @Query private var states: [StateEntry]
    @Query private var results: [TaskResult]
    @Query private var notes: [DiaryNote]
    @State private var editing: Medication?
    @State private var adding = false
    @State private var confirmingDelete = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ZStack {
                CoachBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CoachScreenTitle(title: "마이")
                        CoachSectionHeader(title: "내 약")
                        group {
                            ForEach(medications) { med in
                                row(symbol: "pills.fill", title: med.dose.isEmpty ? med.name : "\(med.name) · \(med.dose)",
                                    detail: med.minutesOfDay.map(\.clockLabel).joined(separator: ", ")) { editing = med }
                            }
                            row(symbol: "plus.circle.fill", title: "약 추가", detail: nil) { adding = true }
                        }
                        CoachSectionHeader(title: "알림")
                        group {
                            row(symbol: notificationStatus == .authorized ? "bell.fill" : "bell.slash.fill",
                                title: notificationStatus == .authorized ? "복약 알림 켜짐" : "복약 알림 꺼짐",
                                detail: notificationStatus == .authorized ? "약 시간과 1시간 뒤 몸 상태를 알려 드려요" : "눌러서 알림을 켜 주세요") {
                                Task { await toggleNotifications() }
                            }
                        }
                        CoachSectionHeader(title: "데이터")
                        group {
                            ShareLink(item: CSVFile(text: CSVExport.make(intakes: intakes, states: states, results: results, notes: notes)),
                                      preview: SharePreview("ParkiCheck 기록.csv")) {
                                rowLabel(symbol: "square.and.arrow.up", title: "기록 내보내기 (CSV)", detail: "모든 기록을 표 파일로 내보내요")
                            }
                            .buttonStyle(CoachPressStyle())
                            row(symbol: "trash.fill", title: "모든 기록 삭제", detail: "이 기기에만 저장돼 있어요. 되돌릴 수 없어요.", tint: CoachStyle.danger) {
                                confirmingDelete = true
                            }
                        }
                        CoachSectionHeader(title: "안내")
                        group {
                            NavigationLink {
                                ZStack { CoachBackground(); ScrollView { NoticeContent().padding(20) } }
                                    .navigationTitle("이 앱에 대하여")
                            } label: {
                                rowLabel(symbol: "info.circle.fill", title: "이 앱에 대하여", detail: nil)
                            }
                            .buttonStyle(CoachPressStyle())
                            if let url = AppConfig.privacyPolicyURL {
                                Link(destination: url) { rowLabel(symbol: "hand.raised.fill", title: "개인정보처리방침", detail: nil) }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { MedicationEditorView(medication: $0) }
            .sheet(isPresented: $adding) { MedicationEditorView(medication: nil) }
            .confirmationDialog("복약 \(intakes.count)건, 몸 상태 \(states.count)건, 움직임 \(results.count)건, 메모 \(notes.count)건을 삭제해요. 되돌릴 수 없어요.",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("모두 삭제", role: .destructive) {
                    try? context.delete(model: MedicationEntry.self)
                    try? context.delete(model: StateEntry.self)
                    try? context.delete(model: TaskResult.self)
                    try? context.delete(model: DiaryNote.self)
                    try? context.save()
                }
            }
            .task { notificationStatus = await NotificationManager.shared.authorizationStatus() }
        }
    }

    private func toggleNotifications() async {
        switch notificationStatus {
        case .notDetermined:
            await NotificationManager.shared.requestAuthorization()
            notificationStatus = await NotificationManager.shared.authorizationStatus()
            await NotificationManager.shared.reschedule(medications)
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .coachSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(symbol: String, title: String, detail: String?, tint: Color = CoachStyle.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(symbol: symbol, title: title, detail: detail, tint: tint) }
            .buttonStyle(CoachPressStyle())
    }

    private func rowLabel(symbol: String, title: String, detail: String?, tint: Color = CoachStyle.ink) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint == CoachStyle.ink ? CoachStyle.accent : tint)
                .frame(width: 31)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(tint)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(CoachStyle.quiet) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(CoachStyle.faint)
        }
        .padding(.horizontal, 16).frame(minHeight: detail == nil ? 56 : 66)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(CoachStyle.stroke).frame(height: 1).padding(.leading, 60) }
    }
}

enum AppConfig {
    /// Required before App Store submission. Set to the published policy URL.
    static let privacyPolicyURL: URL? = nil
}

enum CSVExport {
    static func make(intakes: [MedicationEntry], states: [StateEntry], results: [TaskResult], notes: [DiaryNote]) -> String {
        let iso = ISO8601DateFormatter()
        func text(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var lines = ["type,time,item,side,metric,value,unit,note"]
        for m in intakes.sorted(by: { $0.takenAt < $1.takenAt }) {
            lines.append(["medication", iso.string(from: m.takenAt), text(m.name), "", "dose", text(m.dose), "",
                          text(m.scheduledMinute.map { "scheduled \($0.clockLabel)" } ?? "extra")].joined(separator: ","))
        }
        for s in states.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            lines.append(["state", iso.string(from: s.recordedAt), s.stateRaw, "", "", "", "", text(s.note)].joined(separator: ","))
        }
        for r in results.sorted(by: { $0.startedAt < $1.startedAt }) {
            for metric in r.metrics {
                lines.append(["task", iso.string(from: r.startedAt), r.kindRaw, r.sideRaw ?? "", metric.key,
                              metric.value.map { String(format: "%.4f", $0) } ?? "", metric.unit, text(r.note)].joined(separator: ","))
            }
        }
        for n in notes.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            lines.append(["note", iso.string(from: n.recordedAt), text(n.tags.joined(separator: ";")), "", "", "", "", text(n.text)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

/// Shares the export as a real `.csv` file (not plain text), so it arrives as a spreadsheet attachment.
struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ParkiCheck-records.csv")
            // UTF-8 BOM so spreadsheet apps (e.g. Excel) read Korean text correctly.
            try Data(("\u{FEFF}" + file.text).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
