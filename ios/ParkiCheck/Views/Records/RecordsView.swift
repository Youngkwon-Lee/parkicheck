import Charts
import SwiftData
import SwiftUI

struct RecordsView: View {
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query(sort: \MedicationEntry.takenAt, order: .reverse) private var intakes: [MedicationEntry]
    @Query(sort: \StateEntry.recordedAt, order: .reverse) private var states: [StateEntry]
    @Query(sort: \TaskResult.startedAt, order: .reverse) private var results: [TaskResult]
    @Query(sort: \DiaryNote.recordedAt, order: .reverse) private var notes: [DiaryNote]
    @State private var trendKind: TaskKind = .fingerTapping
    @State private var reportURL: URL?

    private var summary: WeeklySummary { WeeklySummary.make(ReportData.summaryInput(medications, intakes, states, results), now: Date()) }

    var body: some View {
        NavigationStack {
            ZStack {
                CoachBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CoachScreenTitle(title: "기록", subtitle: "지난 7일 동안 기록한 내용이에요.")
                        reportButton
                        summaryGrid
                        stateChart
                        trendChart
                        timeline
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(intakes.count)-\(states.count)-\(results.count)-\(medications.count)-\(notes.count)") {
                reportURL = ReportRenderer.makePDF(summary: summary, medications: medications, results: results, states: states, notes: notes)
            }
        }
    }

    @ViewBuilder private var reportButton: some View {
        if let reportURL {
            ShareLink(item: reportURL, preview: SharePreview("ParkiCheck 진료 리포트")) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.richtext.fill").font(.system(size: 20)).foregroundStyle(CoachStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("진료 리포트 공유").font(.system(size: 17, weight: .semibold)).foregroundStyle(CoachStyle.ink)
                        Text("진료 때 의료진에게 보여 주세요 (PDF)").font(.subheadline).foregroundStyle(CoachStyle.quiet)
                    }
                    Spacer()
                    Image(systemName: "square.and.arrow.up").foregroundStyle(CoachStyle.quiet)
                }
                .padding(16).frame(minHeight: 64)
                .coachSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), accent: CoachStyle.accent)
            }
            .buttonStyle(CoachPressStyle())
        }
    }

    private var summaryGrid: some View {
        let s = summary
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            CoachStat(title: "복약 기록", value: s.adherencePercent.map { "\($0)%" } ?? "—",
                      detail: s.scheduledDoses > 0 ? "\(s.takenOnSchedule)/\(s.scheduledDoses)회" : "약을 등록해 주세요")
            CoachStat(title: "약효 떨어짐", value: "\(s.states.off)회", detail: s.busiestOffPart.map { "주로 \($0.rawValue)" })
            CoachStat(title: "이상운동", value: "\(s.states.dyskinesia)회", detail: "몸 상태 기록 \(s.states.total)회 중")
            CoachStat(title: "움직임 기록한 날", value: "\(s.checkDays)일", detail: tappingDetail(s))
        }
    }

    private func tappingDetail(_ s: WeeklySummary) -> String? {
        s.tappingRateThisWeek.map { "탭핑 초당 \($0.formatted(.number.precision(.fractionLength(1))))회" }
    }

    @ViewBuilder private var stateChart: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let recent = states.filter { $0.recordedAt >= weekAgo }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionHeader(title: "시간대별 몸 상태")
                Chart {
                    ForEach(WeeklySummary.DayPart.allCases, id: \.self) { part in
                        ForEach(PatientState.allCases) { state in
                            let count = recent.filter {
                                $0.state == state && WeeklySummary.DayPart.of(hour: Calendar.current.component(.hour, from: $0.recordedAt)) == part
                            }.count
                            BarMark(x: .value("시간대", part.rawValue), y: .value("횟수", count))
                                .foregroundStyle(by: .value("상태", state.shortLabel))
                        }
                    }
                }
                .chartForegroundStyleScale([PatientState.good.shortLabel: CoachStyle.tint(for: .good),
                                            PatientState.off.shortLabel: CoachStyle.tint(for: .off),
                                            PatientState.dyskinesia.shortLabel: CoachStyle.tint(for: .dyskinesia)])
                .chartXAxis { AxisMarks { AxisValueLabel().font(.subheadline).foregroundStyle(CoachStyle.quiet) } }
                .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(CoachStyle.stroke); AxisValueLabel().foregroundStyle(CoachStyle.quiet) } }
                .frame(height: 200)
                .coachCard()
            }
        }
    }

    @ViewBuilder private var trendChart: some View {
        let kinds = TaskKind.allCases.filter { k in results.contains { $0.kind == k } }
        if !kinds.isEmpty {
            let kind = kinds.contains(trendKind) ? trendKind : kinds[0]
            let points = results.filter { $0.kind == kind && $0.primaryValue != nil }
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionHeader(title: "움직임 추이")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(kinds) { k in
                            Button(k.title) { trendKind = k }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(k == kind ? CoachStyle.onPrimary : CoachStyle.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(k == kind ? CoachStyle.primary : CoachStyle.surface, in: Capsule())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.primaryMetricLabel).font(.subheadline).foregroundStyle(CoachStyle.quiet)
                    Chart(points) { r in
                        LineMark(x: .value("날짜", r.startedAt), y: .value(kind.primaryMetricLabel, r.primaryValue ?? 0))
                            .foregroundStyle(by: .value("쪽", r.side?.sideLabel ?? "전체"))
                        PointMark(x: .value("날짜", r.startedAt), y: .value(kind.primaryMetricLabel, r.primaryValue ?? 0))
                            .foregroundStyle(by: .value("쪽", r.side?.sideLabel ?? "전체"))
                    }
                    .chartForegroundStyleScale(["오른쪽": CoachStyle.primary, "왼쪽": CoachStyle.accent, "전체": CoachStyle.ok])
                    .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(CoachStyle.quiet) } }
                    .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(CoachStyle.stroke); AxisValueLabel().foregroundStyle(CoachStyle.quiet) } }
                    .frame(height: 200)
                    .accessibilityLabel("\(kind.title) \(kind.primaryMetricLabel) 추이")
                }
                .coachCard()
            }
        }
    }

    @ViewBuilder private var timeline: some View {
        let items = TimelineItem.build(intakes: intakes, states: states, results: results, notes: notes, days: 7)
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionHeader(title: "최근 기록")
            if items.isEmpty {
                CoachNotice(symbol: "tray", text: "아직 기록이 없어요. 홈에서 약과 몸 상태를 기록해 보세요.")
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(40)) { item in
                        NavigationLink {
                            item.destination
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: item.symbol).font(.system(size: 17)).foregroundStyle(item.tint)
                                    .frame(width: 36, height: 36).background(CoachStyle.raised, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CoachStyle.ink)
                                    Text(item.date.formatted(.dateTime.month().day().weekday().hour().minute()))
                                        .font(.footnote).foregroundStyle(CoachStyle.quiet)
                                }
                                Spacer()
                                if item.hasDetail {
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(CoachStyle.faint)
                                }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                        }
                        .disabled(!item.hasDetail)
                        .buttonStyle(CoachPressStyle())
                        Rectangle().fill(CoachStyle.stroke).frame(height: 1).padding(.leading, 65)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .coachSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct TimelineItem: Identifiable {
    let id: String
    let date: Date
    let title: String
    let symbol: String
    let tint: Color
    let result: TaskResult?

    var hasDetail: Bool { result != nil }
    @ViewBuilder var destination: some View {
        if let result { ResultDetailView(result: result) }
    }

    static func build(intakes: [MedicationEntry], states: [StateEntry], results: [TaskResult], notes: [DiaryNote], days: Int) -> [TimelineItem] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var items: [TimelineItem] = []
        items += intakes.filter { $0.takenAt >= since }.map {
            TimelineItem(id: "m\($0.id)", date: $0.takenAt, title: $0.dose.isEmpty ? "\($0.name) 복용" : "\($0.name) \($0.dose) 복용",
                         symbol: "pills.fill", tint: CoachStyle.primary, result: nil)
        }
        items += states.filter { $0.recordedAt >= since }.map {
            TimelineItem(id: "s\($0.id)", date: $0.recordedAt, title: $0.state.label, symbol: $0.state.symbol,
                         tint: CoachStyle.tint(for: $0.state), result: nil)
        }
        items += results.filter { $0.startedAt >= since }.map {
            TimelineItem(id: "r\($0.id)", date: $0.startedAt, title: [$0.side?.label, $0.kind.title].compactMap { $0 }.joined(separator: " "),
                         symbol: $0.kind.symbol, tint: CoachStyle.accent, result: $0)
        }
        items += notes.filter { $0.recordedAt >= since }.map {
            TimelineItem(id: "n\($0.id)", date: $0.recordedAt, title: $0.tags.isEmpty ? $0.text : "\($0.tags.joined(separator: ", ")) · \($0.text)",
                         symbol: $0.tags.contains("넘어짐") ? "exclamationmark.triangle.fill" : "text.bubble.fill",
                         tint: $0.tags.contains("넘어짐") ? CoachStyle.warn : CoachStyle.accent, result: nil)
        }
        return items.sorted { $0.date > $1.date }
    }
}

struct ResultDetailView: View {
    @Bindable var result: TaskResult

    var body: some View {
        ZStack {
            CoachBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CoachScreenTitle(title: [result.side?.label, result.kind.title].compactMap { $0 }.joined(separator: " "),
                                     subtitle: result.startedAt.formatted(date: .long, time: .shortened))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(result.metrics) { CoachStat(title: $0.label, value: $0.formatted) }
                    }
                    CoachSectionHeader(title: "메모")
                    TextField("", text: $result.note, prompt: Text("메모").foregroundStyle(CoachStyle.quiet), axis: .vertical).coachField()
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum ReportData {
    static func summaryInput(_ medications: [Medication], _ intakes: [MedicationEntry], _ states: [StateEntry], _ results: [TaskResult]) -> WeeklySummary.Input {
        let active = medications.filter(\.isActive)
        return WeeklySummary.Input(
            medications: active.map { .init(id: $0.id, name: $0.name, dose: $0.dose, minutesOfDay: $0.minutesOfDay) },
            medicationCreatedAt: Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.createdAt) }),
            intakes: intakes.map { .init(medicationID: $0.medicationID, scheduledMinute: $0.scheduledMinute, takenAt: $0.takenAt) },
            states: states.map { ($0.recordedAt, $0.state) },
            tapping: results.filter { $0.kind == .fingerTapping }.compactMap { r in r.primaryValue.map { (r.startedAt, $0) } },
            checkDates: results.map(\.startedAt))
    }
}
