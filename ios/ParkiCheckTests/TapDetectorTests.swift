import CoreGraphics
import XCTest
@testable import ParkiCheck

final class TapDetectorTests: XCTestCase {
    /// Hand size (wrist → middle MCP) is 100 px, so the thumb–index distance equals the ratio × 100.
    private func sample(_ t: TimeInterval, opening ratio: Double) -> HandSample {
        HandSample(timestamp: t,
                   thumbTip: CGPoint(x: 200, y: 200),
                   indexTip: CGPoint(x: 200 + ratio * 100, y: 200),
                   wrist: CGPoint(x: 100, y: 300),
                   middleMCP: CGPoint(x: 100, y: 200))
    }

    func testCountsOneTapPerOpenCloseCycle() {
        var detector = TapDetector()
        var t = 0.0
        for _ in 0..<5 {
            detector.process(sample(t, opening: 0.6)); t += 0.1
            detector.process(sample(t, opening: 0.1)); t += 0.1
        }
        XCTAssertEqual(detector.taps.count, 5)
        XCTAssertEqual(detector.taps.first!.amplitude, 0.6, accuracy: 1e-9)
    }

    func testHysteresisIgnoresJitterNearThreshold() {
        var detector = TapDetector()
        detector.process(sample(0.0, opening: 0.6))
        detector.process(sample(0.2, opening: 0.2))   // closes → tap
        detector.process(sample(0.4, opening: 0.3))   // between thresholds: still closed
        detector.process(sample(0.6, opening: 0.2))   // no new tap
        XCTAssertEqual(detector.taps.count, 1)
    }

    func testCooldownSuppressesDoubleCount() {
        var detector = TapDetector()
        detector.process(sample(0.00, opening: 0.6))
        detector.process(sample(0.03, opening: 0.1))  // tap
        detector.process(sample(0.06, opening: 0.6))
        detector.process(sample(0.09, opening: 0.1))  // within 140 ms → ignored
        XCTAssertEqual(detector.taps.count, 1)
    }

    func testIgnoresDegenerateHand() {
        var detector = TapDetector()
        let s = HandSample(timestamp: 0, thumbTip: .zero, indexTip: .zero, wrist: .zero, middleMCP: .zero)
        XCTAssertNil(detector.process(s))
        XCTAssertTrue(detector.taps.isEmpty)
    }
}
