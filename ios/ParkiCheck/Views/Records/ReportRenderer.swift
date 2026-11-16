import SwiftUI

/// Renders a one-page clinician report (light, printable) to a PDF in the temporary directory.
@MainActor
enum ReportRenderer {
    static func makePDF(summary: WeeklySummary, medications: [Medication], results: [TaskResult], states: [StateEntry], notes: [DiaryNote]) -> URL? {
        let page = ReportPage(summary: summary, medications: medications.filter(\.isActive), results: results, states: states, notes: notes)
            .frame(width: 595)
        let renderer = ImageRenderer(content: page)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ParkiCheck-report.pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

struct ReportPage: View {
    let summary: WeeklySummary
    let medications: [Medication]
    let results: [TaskResult]
    let states: [StateEntry]
    let notes: [DiaryNote]

    private var weekAgo: Date { Calendar.current.date(byAdding: .day, value: -7, to: Date())! }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ParkiCheck 자가 기록 리포트").font(.system(size: 22, weight: .bold))
                Text("기간: \(weekAgo.formatted(date: .abbreviated, time: .omitted)) – \(Date().formatted(date: .abbreviated, time: .omitted)) · 환자가 직접 기록한 내용")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            section("복약") {
                ForEach(medications) { med in
                    row(med.dose.isEmpty ? med.name : "\(med.name) \(med.dose)", med.minutesOfDay.map(\.clockLabel).joined(separator: ", "))
                }
                row("예정된 복약 중 기록", summary.adherencePercent.map { "\(summary.takenOnSchedule)/\(summary.scheduledDoses)회 (\($0)%)" } ?? "—")
            }
            section("환자 보고 상태 (지난 7일)") {
                row("괜찮음 / 약효 떨어짐 / 이상운동", "\(summary.states.good) / \(summary.states.off) / \(summary.states.dyskinesia)회")
                ForEach(WeeklySummary.DayPart.allCases, id: \.self) { part in
                    let partStates = states.filter {
                        $0.recordedAt >= weekAgo && WeeklySummary.DayPart.of(hour: Calendar.current.component(.hour, from: $0.recordedAt)) == part
                    }
                    if !partStates.isEmpty {
                        row("  \(part.rawValue)", PatientState.allCases.map { s in "\(s.shortLabel) \(partStates.filter { $0.state == s }.count)" }.joined(separator: " · "))
                    }
                }
            }
            let weekNotes = notes.filter { $0.recordedAt >= weekAgo }
            if !weekNotes.isEmpty {
                section("환자가 말한 증상·메모 (지난 7일)") {
                    let tags = Dictionary(grouping: weekNotes.flatMap(\.tags), by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
                    if !tags.isEmpty {
                        row("증상 언급", tags.map { "\($0.key) \($0.value)회" }.joined(separator: " · "))
                    }
                    ForEach(weekNotes.prefix(8)) { note in
                        row(note.recordedAt.formatted(.dateTime.month().day().hour().minute()), note.text)
                    }
                }
            }
            section("움직임 기록 (지난 7일, 평균)") {
                ForEach(TaskKind.allCases) { kind in
                    ForEach(sides(for: kind), id: \.self) { side in
                        let values = results.filter { $0.kind == kind && $0.side == side && $0.startedAt >= weekAgo }.compactMap(\.primaryValue)
                        if !values.isEmpty {
                            let mean = values.reduce(0, +) / Double(values.count)
                            row([side?.label, kind.title].compactMap { $0 }.joined(separator: " "),
                                "\(kind.primaryMetricLabel) \(mean.formatted(.number.precision(.fractionLength(1)))) (\(values.count)회 기록)")
                        }
                    }
                }
            }
            Text("이 리포트는 환자가 앱에 직접 기록한 내용과 카메라로 측정한 움직임 수치를 요약한 것으로, 진단이나 치료 판단을 위한 의료기기 결과가 아닙니다. 수치는 촬영 환경에 따라 달라질 수 있습니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func sides(for kind: TaskKind) -> [Hand?] { kind.needsSide ? [.right, .left] : [nil] }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .bold))
            Divider()
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.trailing)
        }
    }
}
