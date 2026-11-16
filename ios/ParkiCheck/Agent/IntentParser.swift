import Foundation

/// What the patient asked for, parsed on-device from typed or spoken Korean.
/// Deterministic keyword rules: nothing is sent to a server, and the agent only records
/// what the patient says or opens app features. It never interprets symptoms or advises.
enum AgentIntent: Equatable {
    case medicationTaken(medicationHint: String?, at: Date?)
    case medicationNotTaken
    case state(PatientState, note: String)
    case symptom(tags: [String], note: String)
    case startCheck(TaskKind?)
    case nextDose
    case weeklySummary
    case addMedication
    case help
    case note(String)
}

enum IntentParser {
    /// Symptom words recorded as diary tags (patient's own words are kept as the note).
    static let symptomTags: [(tag: String, words: [String])] = [
        ("넘어짐", ["넘어졌", "넘어질", "낙상", "주저앉"]),
        ("떨림", ["떨려", "떨림", "떨리", "후들"]),
        ("어지러움", ["어지러", "어지럼", "핑 돌"]),
        ("수면", ["잠을 못", "못 잤", "잠이 안", "불면", "자다가 깼"]),
        ("통증", ["아파", "아프", "통증", "쑤셔", "저려"]),
        ("변비", ["변비", "변을 못"]),
        ("발이 붙음", ["발이 안 떨어", "발이 붙", "얼어붙"]),
        ("삼킴", ["삼키기", "사레"]),
        ("기분", ["우울", "불안", "기분이 안"]),
    ]

    static let offWords = ["약효", "약 효과", "굳", "뻣뻣", "안 움직", "잘 안 움직", "몸이 무거", "느려", "오프", "off", "OFF"]
    static let dyskinesiaWords = ["저절로", "꼬여", "꼬이", "제멋대로", "춤추", "이상운동", "흐느적", "몸이 흔들려"]
    static let goodWords = ["괜찮", "좋아", "좋은", "좋다", "편해", "잘 움직", "컨디션 좋", "온 상태", "ON"]
    static let negations = ["안 먹", "못 먹", "깜빡", "까먹", "잊어버", "안먹", "못먹"]

    static func parse(_ raw: String, medicationNames: [String] = [], now: Date = Date(), calendar: Calendar = .current) -> AgentIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .help }
        let compact = text.replacingOccurrences(of: " ", with: "")

        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) || compact.contains($0.replacingOccurrences(of: " ", with: "")) } }

        if has(["도움말", "뭐 할 수", "뭘 할 수", "사용법"]) { return .help }
        if has(["약 등록", "약 추가", "약 바뀌", "약 바꿔", "새 약"]) { return .addMedication }
        if has(["다음 약", "언제 먹", "약 시간", "몇 시에 먹"]) { return .nextDose }
        if has(["요약", "이번 주", "이번주", "리포트", "보고서", "일주일"]) { return .weeklySummary }

        let mentionsMedication = has(["약", "먹었", "복용"]) || medicationNames.contains { !$0.isEmpty && text.contains($0) }
        if mentionsMedication, has(negations) { return .medicationNotTaken }
        if has(["먹었", "복용했", "약 먹", "먹음", "챙겨 먹", "삼켰"]) {
            let hint = medicationNames.first { !$0.isEmpty && text.contains($0) }
            return .medicationTaken(medicationHint: hint, at: parseTime(text, now: now, calendar: calendar))
        }

        if has(["검사", "체크", "기록 시작", "측정"]) || has(["탭핑"]) {
            if has(["탭핑", "손가락"]) { return .startCheck(.fingerTapping) }
            if has(["걷기", "보행"]) { return .startCheck(.gait) }
            if has(["떨림"]) { return .startCheck(.restTremor) }
            return .startCheck(nil)
        }

        // Falls and other safety-relevant symptoms are recorded before state words,
        // so "넘어졌는데 괜찮아" keeps the fall.
        let tags = symptomTags.filter { has($0.words) }.map(\.tag)
        if tags.contains("넘어짐") { return .symptom(tags: tags, note: text) }

        if has(dyskinesiaWords) { return .state(.dyskinesia, note: text) }
        if has(offWords) { return .state(.off, note: text) }
        if !tags.isEmpty { return .symptom(tags: tags, note: text) }
        if has(goodWords) { return .state(.good, note: text) }
        return .note(text)
    }

    /// Understands "2시에", "오후 2시 반", "14시 30분", "30분 전", "1시간 전", "아까" (= now).
    static func parseTime(_ text: String, now: Date, calendar: Calendar = .current) -> Date? {
        if let m = firstMatch(#"(\d{1,3})\s*분\s*전"#, in: text), let minutes = Int(m[1]) {
            return now.addingTimeInterval(TimeInterval(-minutes * 60))
        }
        if let m = firstMatch(#"(\d{1,2})\s*시간\s*전"#, in: text), let hours = Int(m[1]) {
            return now.addingTimeInterval(TimeInterval(-hours * 3600))
        }
        guard let m = firstMatch(#"(오전|오후|아침|저녁|밤|점심)?\s*(\d{1,2})\s*시\s*(반|(\d{1,2})\s*분)?"#, in: text),
              var hour = Int(m[2]) else { return nil }
        let minute = m[3] == "반" ? 30 : Int(m[4]) ?? 0
        let period = m[1]
        if ["오후", "저녁", "밤"].contains(period), hour < 12 { hour += 12 }
        if period == "점심", hour < 6 { hour += 12 }
        if ["오전", "아침"].contains(period), hour == 12 { hour = 0 }
        if period.isEmpty, hour < 12 {
            // No period given: pick the most recent past occurrence (e.g. "2시" at 15:00 → 14:00).
            let nowHour = calendar.component(.hour, from: now)
            if hour + 12 <= nowHour { hour += 12 }
        }
        guard hour < 24, minute < 60,
              var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if date > now.addingTimeInterval(5 * 60) { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        return date
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
