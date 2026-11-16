import XCTest
@testable import ParkiCheck

final class IntentParserTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private var afternoon: Date { cal.date(bySettingHour: 15, minute: 10, second: 0, of: Date())! }

    private func parse(_ text: String, meds: [String] = ["마도파", "미라펙스"]) -> AgentIntent {
        IntentParser.parse(text, medicationNames: meds, now: afternoon, calendar: cal)
    }

    func testMedicationTaken() {
        XCTAssertEqual(parse("약 먹었어"), .medicationTaken(medicationHint: nil, at: nil))
        XCTAssertEqual(parse("마도파 먹었어요"), .medicationTaken(medicationHint: "마도파", at: nil))
    }

    func testMedicationWithTime() {
        guard case .medicationTaken(_, let at?) = parse("2시에 약 먹었어") else { return XCTFail() }
        XCTAssertEqual(cal.component(.hour, from: at), 14)
        guard case .medicationTaken(_, let half?) = parse("오후 1시 반에 마도파 먹었어") else { return XCTFail() }
        XCTAssertEqual(cal.component(.hour, from: half), 13)
        XCTAssertEqual(cal.component(.minute, from: half), 30)
        guard case .medicationTaken(_, let ago?) = parse("30분 전에 약 먹었어") else { return XCTFail() }
        XCTAssertEqual(afternoon.timeIntervalSince(ago), 30 * 60, accuracy: 1)
    }

    func testFutureTimeWithoutPeriodMeansEarlierToday() {
        // "11시" said at 15:10 means 11:00 this morning, not 23:00.
        guard case .medicationTaken(_, let at?) = parse("11시에 약 먹었어") else { return XCTFail() }
        XCTAssertEqual(cal.component(.hour, from: at), 11)
        XCTAssertTrue(cal.isDate(at, inSameDayAs: afternoon))
    }

    func testNegationIsNotLoggedAsTaken() {
        XCTAssertEqual(parse("점심 약을 깜빡하고 안 먹었어"), .medicationNotTaken)
    }

    func testStates() {
        XCTAssertEqual(parse("몸이 굳어서 잘 안 움직여"), .state(.off, note: "몸이 굳어서 잘 안 움직여"))
        XCTAssertEqual(parse("몸이 저절로 꼬여"), .state(.dyskinesia, note: "몸이 저절로 꼬여"))
        XCTAssertEqual(parse("오늘은 괜찮아"), .state(.good, note: "오늘은 괜찮아"))
    }

    func testFallIsKeptEvenWithGoodWords() {
        XCTAssertEqual(parse("아침에 넘어졌는데 지금은 괜찮아"), .symptom(tags: ["넘어짐"], note: "아침에 넘어졌는데 지금은 괜찮아"))
    }

    func testSymptomAndNote() {
        XCTAssertEqual(parse("손이 계속 떨려"), .symptom(tags: ["떨림"], note: "손이 계속 떨려"))
        XCTAssertEqual(parse("손주가 놀러 왔다"), .note("손주가 놀러 왔다"))
    }

    func testCommands() {
        XCTAssertEqual(parse("탭핑 검사 할래"), .startCheck(.fingerTapping))
        XCTAssertEqual(parse("다음 약 언제야"), .nextDose)
        XCTAssertEqual(parse("이번 주 요약 보여줘"), .weeklySummary)
        XCTAssertEqual(parse("새 약 추가할래"), .addMedication)
    }
}
