import CoreGraphics
import XCTest
@testable import ParkiCheck

final class TremorSpectrumTests: XCTestCase {
    private func samples(freq: Double, amp: Double, seconds: Double = 15, fps: Double = 30, jitter: Bool = true) -> [TremorSpectrum.Sample] {
        var rng = SystemRandomNumberGenerator()
        return (0..<Int(seconds * fps)).map { i in
            // Irregular frame times, like a real camera.
            let t = Double(i) / fps + (jitter ? Double.random(in: -0.004...0.004, using: &rng) : 0)
            return .init(t: t, x: 200, y: 300 + amp * sin(2 * .pi * freq * t))
        }
    }

    func testFindsFiveHertzTremorAndItsAmplitude() throws {
        let r = try XCTUnwrap(TremorSpectrum.analyze(samples(freq: 5, amp: 4)))
        XCTAssertEqual(r.frequency, 5, accuracy: 0.15)
        XCTAssertEqual(r.amplitude, 4, accuracy: 0.6)
        XCTAssertTrue(r.isClear)
    }

    func testNoiseIsNotReportedAsClearTremor() throws {
        let noise = (0..<450).map { i in
            TremorSpectrum.Sample(t: Double(i) / 30, x: 200 + Double.random(in: -1...1), y: 300 + Double.random(in: -1...1))
        }
        let r = try XCTUnwrap(TremorSpectrum.analyze(noise))
        XCTAssertFalse(r.isClear)
    }

    func testSlowDriftDoesNotDominate() throws {
        var s = samples(freq: 6, amp: 2)
        s = s.map { .init(t: $0.t, x: $0.x + $0.t * 5, y: $0.y + $0.t * 8) }   // hand slowly drifting
        let r = try XCTUnwrap(TremorSpectrum.analyze(s))
        XCTAssertEqual(r.frequency, 6, accuracy: 0.15)
    }

    func testTooShortRecordingReturnsNil() {
        XCTAssertNil(TremorSpectrum.analyze(samples(freq: 5, amp: 4, seconds: 2)))
    }
}

final class BodyAnalyzerTests: XCTestCase {
    private func bodyFrame(_ t: Double, ankleLift: Double) -> TrackerFrame {
        var f = TrackerFrame(timestamp: t, imageSize: CGSize(width: 1080, height: 1920))
        f.body = BodyPoints(points: [.rightKnee: CGPoint(x: 500, y: 1400), .rightAnkle: CGPoint(x: 500, y: 1600 - ankleLift)])
        return f
    }

    func testToeTapAmplitudeIsPeakLiftNotThreshold() {
        var a = LiftCycleAnalyzer.toeTapping(side: .right)
        var t = 0.0
        a.process(bodyFrame(t, ankleLift: 0))   // baseline
        for _ in 0..<4 {
            for lift in [0.0, 20, 60, 80, 60, 20, 0] {   // shank 200px → peak 0.4
                t += 0.05
                a.process(bodyFrame(t, ankleLift: lift))
            }
        }
        XCTAssertEqual(a.events.count, 4)
        XCTAssertEqual(a.events.first?.amplitude ?? 0, 0.4, accuracy: 0.02)   // not the 0.12 threshold
    }

    func testIgnoresOtherSide() {
        var a = LiftCycleAnalyzer.toeTapping(side: .left)
        for i in 0..<20 { a.process(bodyFrame(Double(i) * 0.05, ankleLift: i.isMultiple(of: 2) ? 0 : 80)) }
        XCTAssertTrue(a.events.isEmpty)
    }
}

final class HandAnalyzerTests: XCTestCase {
    /// A hand with wrist at origin-ish; `open` scales fingertip distance from the palm.
    private func handFrame(_ t: Double, open: Double, flip: Bool = false) -> TrackerFrame {
        var f = TrackerFrame(timestamp: t, imageSize: CGSize(width: 1080, height: 1920))
        let wrist = CGPoint(x: 500, y: 900)
        let mcpX: (CGFloat) -> CGFloat = { flip ? 500 - $0 : 500 + $0 }
        let mcps = [CGPoint(x: mcpX(-30), y: 800), CGPoint(x: mcpX(-10), y: 800), CGPoint(x: mcpX(10), y: 800), CGPoint(x: mcpX(30), y: 800)]
        let palm = CGPoint.mean(mcps)
        let tips = mcps.map { CGPoint(x: $0.x, y: palm.y - CGFloat(open * 100)) }   // hand size = 100px
        f.hand = HandPoints(wrist: wrist, thumbTip: CGPoint(x: 450, y: 820),
                            indexMCP: mcps[0], middleMCP: CGPoint(x: 500, y: 800), ringMCP: mcps[2], littleMCP: mcps[3],
                            indexTip: tips[0], middleTip: tips[1], ringTip: tips[2], littleTip: tips[3])
        return f
    }

    func testHandMovementNeedsFullCloseBetweenCycles() {
        var a = HandMovementAnalyzer()
        var t = 0.0
        for open in [0.3, 1.0, 0.65, 1.0, 0.3, 1.0] {   // the 0.65 dip is not a full close
            a.process(handFrame(t, open: open)); t += 0.4
        }
        XCTAssertEqual(a.events.count, 2)
    }

    func testPronationCountsEachFlip() {
        var a = PronationAnalyzer()
        var t = 0.0
        for i in 0..<6 {
            a.process(handFrame(t, open: 1, flip: i.isMultiple(of: 2))); t += 0.4
        }
        XCTAssertEqual(a.events.count, 5)
    }
}

final class ScheduleTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func today(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date())! }

    func testSlotStatuses() {
        let id = UUID()
        let med = DoseSchedule.MedicationInfo(id: id, name: "약", dose: "1정", minutesOfDay: [8 * 60, 13 * 60, 18 * 60])
        let intakes = [DoseSchedule.Intake(medicationID: id, scheduledMinute: 8 * 60, takenAt: today(8, 5))]
        let slots = DoseSchedule.slots(for: [med], intakes: intakes, now: today(12, 45), calendar: cal)
        XCTAssertEqual(slots.map(\.status), [.taken(today(8, 5)), .due, .upcoming])
        XCTAssertEqual(DoseSchedule.next(in: slots)?.minute, 13 * 60)
    }

    func testMissedAfterTwoHours() {
        let med = DoseSchedule.MedicationInfo(id: UUID(), name: "약", dose: "", minutesOfDay: [8 * 60])
        let slots = DoseSchedule.slots(for: [med], intakes: [], now: today(10, 30), calendar: cal)
        XCTAssertEqual(slots.first?.status, .missed)
    }

    func testWeeklySummaryCountsOffByDayPart() {
        let now = today(20)
        let input = WeeklySummary.Input(medications: [], medicationCreatedAt: [:], intakes: [],
                                        states: [(today(9), .off), (today(15), .off), (today(16), .off), (today(10), .good)],
                                        tapping: [(today(9), 4.0), (today(19), 5.0)], checkDates: [today(9)])
        let s = WeeklySummary.make(input, now: now, calendar: cal)
        XCTAssertEqual(s.states.off, 3)
        XCTAssertEqual(s.busiestOffPart, .afternoon)
        XCTAssertEqual(s.tappingRateThisWeek ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertEqual(s.checkDays, 1)
    }
}
