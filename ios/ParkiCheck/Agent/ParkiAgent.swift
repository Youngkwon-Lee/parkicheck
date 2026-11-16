import Foundation
import SwiftData
import SwiftUI

/// The home coach. It runs entirely on the device: it understands typed or spoken Korean
/// with `IntentParser`, records what the patient reports (intake, state, symptoms, notes),
/// and opens app features. It never interprets symptoms, judges drug effect, or advises
/// on treatment.
@MainActor
final class ParkiAgent: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        var question: String?
        var card: Card
    }

    struct Card {
        enum Status { case proposal, done, attention, info }
        var status: Status? = nil
        var title: String? = nil
        var lines: [String] = []
        var actions: [Action] = []
        /// Actions shown as full-width rows (state choices) instead of a pill row.
        var stacked = false
    }

    struct Action: Identifiable {
        enum Style { case primary, secondary, state(PatientState) }
        let id = UUID()
        let title: String
        var style: Style = .secondary
        /// One-shot actions (logging an intake or a state) disappear once used, so the same
        /// card cannot record twice. Navigation actions stay.
        var consumes = true
        let perform: @MainActor () -> Void
    }

    @Published private(set) var messages: [Message] = []

    private let context: ModelContext
    private weak var router: AppRouter?
    var openMedicationEditor: () -> Void = {}
    var requestNotifications: () async -> Void = {}
    private var greeted = false
    /// The greeting's "what to do now" card, refreshed when the schedule changes.
    private var priorityMessageID: UUID?
    private var knownMedicationCount: Int?

    init(context: ModelContext, router: AppRouter) {
        self.context = context
        self.router = router
    }

    // MARK: Data

    private var medications: [Medication] {
        (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.isActive }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private var recentIntakes: [MedicationEntry] {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        return (try? context.fetch(FetchDescriptor<MedicationEntry>(predicate: #Predicate { $0.takenAt >= since }))) ?? []
    }

    private func slots(now: Date = Date()) -> [DoseSlot] {
        DoseSchedule.slots(for: medications.map { .init(id: $0.id, name: $0.name, dose: $0.dose, minutesOfDay: $0.minutesOfDay) },
                           intakes: recentIntakes.map { .init(medicationID: $0.medicationID, scheduledMinute: $0.scheduledMinute, takenAt: $0.takenAt) },
                           now: now)
    }

    // MARK: Conversation

    /// Opens the conversation with one short greeting and, at most, the single most
    /// important thing to do now. Everything else is one question or one chip away.
    func greet(notificationsAuthorized: Bool) {
        guard !greeted else { return }
        greeted = true
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 5 ? "늦은 시간이에요" : hour < 11 ? "좋은 아침이에요" : hour < 17 ? "안녕하세요" : hour < 22 ? "편안한 저녁이에요" : "늦은 시간이에요"
        append(nil, Card(status: .info, title: "\(hello). 오늘 어떠세요?",
                         lines: ["말하거나 적어 주시면 제가 기록할게요."]))
        knownMedicationCount = medications.count
        if let card = priorityCard(notificationsAuthorized: notificationsAuthorized) {
            append(nil, card)
            priorityMessageID = messages.last?.id
        }
    }

    /// Called when the medication list changes (added, edited, removed). Replaces the stale
    /// "what to do now" card and confirms a newly registered medication in the conversation.
    func medicationsChanged(notificationsAuthorized: Bool) {
        guard greeted else { return }
        let meds = medications
        let previous = knownMedicationCount ?? meds.count
        knownMedicationCount = meds.count

        refreshPriority(notificationsAuthorized: notificationsAuthorized)

        if meds.count > previous, let added = meds.last {
            let times = added.minutesOfDay.map(\.clockLabel).joined(separator: ", ")
            var card = Card(status: .done, title: "\(added.name)을 등록했어요.",
                            lines: [notificationsAuthorized ? "\(times)에 알림으로 챙겨 드릴게요." : "\(times)에 드시는 약으로 기록할게요."])
            if let next = DoseSchedule.next(in: slots()) { card.lines.append("다음 약은 \(next.minute.clockLabel) \(next.name)이에요.") }
            append(nil, card)
        }
    }

    /// Replaces the greeting's "what to do now" card with the current most important item.
    func refreshPriority(notificationsAuthorized: Bool) {
        guard let id = priorityMessageID, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if let card = priorityCard(notificationsAuthorized: notificationsAuthorized) {
            messages[index].card = card
        } else {
            messages.remove(at: index)
            priorityMessageID = nil
        }
    }

    /// Removes a used one-shot action from its card.
    func consume(_ actionID: UUID, in messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].card.actions.contains(where: { $0.id == actionID && $0.consumes }) else { return }
        messages[index].card.actions = []
    }

    private func priorityCard(notificationsAuthorized: Bool) -> Card? {
        if medications.isEmpty { return registerCard() }
        let today = slots()
        if let due = today.first(where: { $0.status == .due }) { return nextDoseCard(for: due) }
        if let missed = today.first(where: { $0.status == .missed }) { return missedCard(missed) }
        if !notificationsAuthorized { return notificationCard() }
        if DailyCheck.completedToday(results: results, now: Date()) < DailyCheck.steps.count { return dailyCheckCard() }
        return nextDoseCard()
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let intent = IntentParser.parse(text, medicationNames: medications.map(\.name))
        append(text, respond(to: intent))
    }

    private func respond(to intent: AgentIntent) -> Card {
        switch intent {
        case .medicationTaken(let hint, let at): return logIntake(hint: hint, at: at)
        case .medicationNotTaken:
            return Card(status: .info, title: "알겠어요. 아직 기록하지 않을게요.",
                        lines: ["드시면 \"약 먹었어\"라고 알려 주세요.", "놓친 약을 어떻게 할지는 처방한 의료진의 안내를 따라 주세요."])
        case .state(let state, let note): return logState(state, note: note)
        case .symptom(let tags, let note): return logSymptom(tags: tags, note: note)
        case .note(let text):
            context.insert(DiaryNote(recordedAt: Date(), text: text))
            try? context.save()
            return Card(status: .done, title: "메모로 남겼어요.", lines: ["진료 리포트에 함께 담을게요."])
        case .startCheck(let kind): return checkCard(kind)
        case .nextDose: return nextDoseCard() ?? Card(status: .info, title: medications.isEmpty ? "등록된 약이 없어요." : "오늘 남은 약이 없어요.",
                                                       actions: medications.isEmpty ? [Action(title: "약 등록하기", style: .primary) { [weak self] in self?.openMedicationEditor() }] : [])
        case .weeklySummary: return weekCard()
        case .addMedication:
            openMedicationEditor()
            return Card(status: .info, title: "약 등록 화면을 열었어요.", lines: ["목록에서 약을 고르고 드시는 시간을 눌러 주세요."])
        case .help:
            return Card(status: .info, title: "이렇게 말해 보세요.",
                        lines: ["\"약 먹었어\" · \"30분 전에 마도파 먹었어\"", "\"몸이 굳어\" · \"몸이 저절로 움직여\" · \"괜찮아\"",
                                "\"아침에 넘어졌어\" · \"손이 떨려\"", "\"탭핑 검사 할래\" · \"다음 약 언제야\" · \"이번 주 요약\""])
        }
    }

    // MARK: Actions

    private func logIntake(hint: String?, at: Date?) -> Card {
        let meds = medications
        guard !meds.isEmpty else { return registerCard() }
        let when = at ?? Date()
        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: when) * 60 + cal.component(.minute, from: when)
        let loggedToday = recentIntakes.filter { cal.isDate($0.takenAt, inSameDayAs: when) }

        func openSlot(_ med: Medication) -> Int? {
            let taken = Set(loggedToday.filter { $0.medicationID == med.id }.compactMap(\.scheduledMinute))
            return med.minutesOfDay.filter { !taken.contains($0) && abs($0 - minuteOfDay) <= 180 }
                .min { abs($0 - minuteOfDay) < abs($1 - minuteOfDay) }
        }

        var targets: [Medication]
        if let hint, let med = meds.first(where: { $0.name == hint }) {
            targets = [med]
        } else {
            targets = meds.filter { openSlot($0) != nil }
            if targets.isEmpty, meds.count == 1 { targets = meds }
        }
        guard !targets.isEmpty else {
            return Card(status: .proposal, title: "어떤 약을 드셨나요?",
                        actions: meds.map { med in Action(title: med.name) { [weak self] in self?.confirmIntake(med, at: when) } })
        }
        var lines: [String] = []
        for med in targets {
            let slot = openSlot(med)
            context.insert(MedicationEntry(takenAt: when, name: med.name, dose: med.dose, medicationID: med.id, scheduledMinute: slot))
            lines.append("\(when.formatted(date: .omitted, time: .shortened)) \(med.name)\(med.dose.isEmpty ? "" : " \(med.dose)")\(slot == nil ? " (추가 복용)" : "")")
        }
        try? context.save()
        if let next = DoseSchedule.next(in: slots()) { lines.append("다음 약은 \(next.minute.clockLabel) \(next.name)이에요.") }
        return Card(status: .done, title: "복약을 기록했어요.", lines: lines)
    }

    private func confirmIntake(_ med: Medication, at: Date) {
        append("\(med.name) 먹었어요", logIntake(hint: med.name, at: at))
    }

    private func logState(_ state: PatientState, note: String?) -> Card {
        context.insert(StateEntry(recordedAt: Date(), state: state, note: note ?? ""))
        try? context.save()
        let line: String
        switch state {
        case .good: line = "괜찮을 때 오늘의 체크를 해 두면 나중에 비교하기 좋아요."
        case .off: line = "약효가 떨어지는 시간이 반복되면 진료 리포트로 의료진에게 보여 주세요."
        case .dyskinesia: line = "언제 생기는지 쌓이면 진료 때 도움이 돼요."
        }
        var card = Card(status: .done, title: "\(Date().formatted(date: .omitted, time: .shortened)) '\(state.shortLabel)'으로 기록했어요.", lines: [line])
        if state == .good, DailyCheck.completedToday(results: results, now: Date()) < DailyCheck.steps.count {
            card.actions = [Action(title: "오늘의 체크 하기", style: .primary, consumes: false) { [weak self] in self?.router?.startDailyCheck() }]
        }
        return card
    }

    private func logSymptom(tags: [String], note: String) -> Card {
        context.insert(DiaryNote(recordedAt: Date(), text: note, tags: tags))
        try? context.save()
        var lines = ["진료 리포트에 함께 담을게요."]
        if tags.contains("넘어짐") {
            lines.insert("다쳤거나 머리를 부딪혔다면 의료진에게 바로 알려 주세요.", at: 0)
        }
        return Card(status: tags.contains("넘어짐") ? .attention : .done, title: "'\(tags.joined(separator: ", "))'을 기록했어요.", lines: lines)
    }

    func recordState(_ state: PatientState) {
        append(state.label, logState(state, note: nil))
    }

    // MARK: Cards

    private var results: [TaskResult] {
        let since = Calendar.current.startOfDay(for: Date())
        return (try? context.fetch(FetchDescriptor<TaskResult>(predicate: #Predicate { $0.startedAt >= since }))) ?? []
    }

    private func registerCard() -> Card {
        Card(status: .proposal, title: "드시는 약을 알려 주세요",
             lines: ["한 번만 등록하면 약 드실 시간에 알림으로 챙겨 드려요.", "알림에서 '먹었어요'만 누르면 기록이 끝나요."],
             actions: [Action(title: "약 등록하기", style: .primary, consumes: false) { [weak self] in self?.openMedicationEditor() }])
    }

    private func notificationCard() -> Card {
        Card(status: .attention, title: "복약 알림이 꺼져 있어요", lines: ["약 드실 시간과 1시간 뒤 몸 상태를 알려 드려요."],
             actions: [Action(title: "알림 켜기", style: .primary, consumes: false) { [weak self] in
                 guard let self else { return }
                 Task {
                     await self.requestNotifications()
                     let authorized = await NotificationManager.shared.authorizationStatus() == .authorized
                     self.refreshPriority(notificationsAuthorized: authorized)
                 }
             }])
    }

    private func missedCard(_ slot: DoseSlot) -> Card {
        Card(status: .attention, title: "\(slot.minute.clockLabel) \(slot.name) 기록이 없어요", lines: ["드셨다면 눌러 주세요."],
             actions: [Action(title: "먹었어요") { [weak self] in self?.logSlot(slot) }])
    }

    private func nextDoseCard(for slot: DoseSlot? = nil) -> Card? {
        guard let next = slot ?? DoseSchedule.next(in: slots()) else { return nil }
        let due = next.status == .due
        return Card(status: due ? .proposal : .info, title: "\(due ? "지금" : "다음 약") · \(next.minute.clockLabel) \(next.name)",
                    lines: [next.dose.isEmpty ? nil : next.dose, due ? "지금 드실 시간이에요." : nil].compactMap { $0 },
                    actions: [Action(title: "먹었어요", style: due ? .primary : .secondary) { [weak self] in self?.logSlot(next) }])
    }

    private func logSlot(_ slot: DoseSlot) {
        guard NotificationManager.logIntake(medicationID: slot.medicationID, minute: slot.minute, in: context) else {
            append("\(slot.name) 먹었어요", Card(status: .info, title: "이미 기록되어 있어요.", lines: ["\(slot.minute.clockLabel) \(slot.name)"]))
            return
        }
        var lines = ["\(slot.minute.clockLabel) \(slot.name)"]
        if let next = DoseSchedule.next(in: slots()) { lines.append("다음 약은 \(next.minute.clockLabel) \(next.name)이에요.") }
        append("\(slot.name) 먹었어요", Card(status: .done, title: "복약을 기록했어요.", lines: lines))
    }

    private func dailyCheckCard() -> Card {
        let done = DailyCheck.completedToday(results: results, now: Date())
        return Card(status: .proposal, title: "오늘의 체크 · 약 2분", lines: ["양손 손가락 탭핑을 기록해요. (\(done)/\(DailyCheck.steps.count))"],
                    actions: [Action(title: done == 0 ? "시작하기" : "이어서 하기", style: .primary, consumes: false) { [weak self] in self?.router?.startDailyCheck() }])
    }

    private func checkCard(_ kind: TaskKind?) -> Card {
        guard let kind else { return dailyCheckCard() }
        if kind.needsSide {
            return Card(status: .proposal, title: kind.title, lines: [kind.setup],
                        actions: [Hand.right, .left].map { side in
                            Action(title: side.sideLabel, style: .primary, consumes: false) { [weak self] in self?.router?.openTask(kind, side: side) }
                        })
        }
        return Card(status: .proposal, title: kind.title, lines: [kind.setup],
                    actions: [Action(title: "시작하기", style: .primary, consumes: false) { [weak self] in self?.router?.openTask(kind, side: nil) }])
    }

    private func weekCard() -> Card {
        let summary = WeeklySummary.make(ReportData.summaryInput(fetchAll(Medication.self), fetchAll(MedicationEntry.self),
                                                                 fetchAll(StateEntry.self), fetchAll(TaskResult.self)), now: Date())
        let lines = WeekText.lines(summary)
        return Card(status: .info, title: "지난 7일 요약", lines: lines.isEmpty ? ["아직 쌓인 기록이 없어요."] : lines,
                    actions: [Action(title: "자세히 보기", consumes: false) { [weak self] in self?.router?.tab = .records }])
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func append(_ question: String?, _ card: Card) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            messages.append(Message(question: question, card: card))
        }
    }
}

enum WeekText {
    static func lines(_ s: WeeklySummary) -> [String] {
        var lines: [String] = []
        if let adherence = s.adherencePercent {
            lines.append("복약 기록 \(s.takenOnSchedule)/\(s.scheduledDoses)회 (\(adherence)%)")
        }
        if s.states.total > 0 {
            var line = "몸 상태 기록 \(s.states.total)회 · 약효 떨어짐 \(s.states.off)회"
            if let part = s.busiestOffPart { line += " (주로 \(part.rawValue))" }
            lines.append(line)
        }
        if let rate = s.tappingRateThisWeek {
            var line = "손가락 탭핑 평균 초당 \(rate.formatted(.number.precision(.fractionLength(1))))회"
            if let last = s.tappingRateLastWeek {
                let diff = rate - last
                line += abs(diff) < 0.05 ? " (지난주와 비슷)" : " (지난주보다 \(abs(diff).formatted(.number.precision(.fractionLength(1)))) \(diff > 0 ? "많음" : "적음"))"
            }
            lines.append(line)
        }
        if s.checkDays > 0 { lines.append("움직임 기록한 날 \(s.checkDays)일") }
        return lines
    }
}
