import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \TapSession.startedAt) private var sessions: [TapSession]
    @Query(sort: \MedicationEntry.takenAt) private var medications: [MedicationEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("안내") {
                    NavigationLink("이 앱에 대하여") { NoticeContent().padding().navigationTitle("이 앱에 대하여") }
                    if let url = AppConfig.privacyPolicyURL {
                        Link("개인정보처리방침", destination: url)
                    }
                }
                Section {
                    ShareLink(item: CSVExport.make(sessions: sessions, medications: medications),
                              preview: SharePreview("ParkiCheck 기록.csv")) {
                        Label("기록 내보내기 (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(sessions.isEmpty && medications.isEmpty)
                } footer: {
                    Text("내보낸 파일을 진료 시 의료진에게 보여 줄 수 있습니다.")
                }
                Section {
                    Button("모든 기록 삭제", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("모든 기록은 이 기기에만 저장됩니다. 삭제하면 되돌릴 수 없습니다.")
                }
            }
            .navigationTitle("설정")
            .confirmationDialog("탭핑 기록 \(sessions.count)개와 복약 기록 \(medications.count)개를 삭제합니다. 되돌릴 수 없습니다.",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("모두 삭제", role: .destructive) {
                    try? modelContext.delete(model: TapSession.self)
                    try? modelContext.delete(model: MedicationEntry.self)
                }
            }
        }
    }
}

enum AppConfig {
    /// Required before App Store submission. Set to the published policy URL.
    static let privacyPolicyURL: URL? = nil
}

enum CSVExport {
    static func make(sessions: [TapSession], medications: [MedicationEntry]) -> String {
        let iso = ISO8601DateFormatter()
        func num(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "" }
        func text(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }

        var lines = ["type,time,hand,tap_count,taps_per_sec,median_interval_ms,interval_cv_pct,mean_amplitude,amplitude_decrement_pct,pause_count,medication,dose,note"]
        for s in sessions {
            lines.append(["tapping", iso.string(from: s.startedAt), s.handRaw, "\(s.tapCount)", num(s.tapsPerSecond),
                          num(s.medianIntervalMs), num(s.intervalCVPercent), num(s.meanAmplitude),
                          num(s.amplitudeDecrementPercent), "\(s.pauseCount)", "", "", text(s.note)].joined(separator: ","))
        }
        for m in medications {
            lines.append(["medication", iso.string(from: m.takenAt), "", "", "", "", "", "", "", "",
                          text(m.name), text(m.dose), text(m.note)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
