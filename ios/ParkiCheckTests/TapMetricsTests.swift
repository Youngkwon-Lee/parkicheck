import XCTest
@testable import ParkiCheck

final class TapMetricsTests: XCTestCase {
    func testEmptyRecording() {
        let m = TapMetrics.compute(taps: [], durationSec: 10)
        XCTAssertEqual(m.tapCount, 0)
        XCTAssertEqual(m.tapsPerSecond, 0)
        XCTAssertNil(m.medianIntervalMs)
        XCTAssertNil(m.intervalCVPercent)
        XCTAssertNil(m.meanAmplitude)
        XCTAssertNil(m.amplitudeDecrementPercent)
        XCTAssertEqual(m.pauseCount, 0)
    }

    func testRegularTappingHasZeroVariation() {
        let taps = (0..<10).map { TapEvent(time: Double($0) * 0.2, amplitude: 0.5) }
        let m = TapMetrics.compute(taps: taps, durationSec: 2)
        XCTAssertEqual(m.tapsPerSecond, 5, accuracy: 1e-9)
        XCTAssertEqual(m.medianIntervalMs!, 200, accuracy: 1e-6)
        XCTAssertEqual(m.intervalCVPercent!, 0, accuracy: 1e-6)
        XCTAssertEqual(m.meanAmplitude!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.amplitudeDecrementPercent!, 0, accuracy: 1e-9)
        XCTAssertEqual(m.pauseCount, 0)
    }

    func testPausesAndMedianInterval() {
        let times = [0.0, 0.2, 0.4, 1.2, 1.4, 2.4]
        let m = TapMetrics.compute(taps: times.map { TapEvent(time: $0, amplitude: 0.4) }, durationSec: 3)
        XCTAssertEqual(m.pauseCount, 2)          // 0.8s and 1.0s gaps
        XCTAssertEqual(m.medianIntervalMs!, 200, accuracy: 1e-6)
    }

    func testAmplitudeDecrementMatchesWebFormula() {
        let amps = [0.6, 0.6, 0.6, 0.3, 0.3, 0.3]
        let taps = amps.enumerated().map { TapEvent(time: Double($0.offset) * 0.25, amplitude: $0.element) }
        let m = TapMetrics.compute(taps: taps, durationSec: 2)
        XCTAssertEqual(m.amplitudeDecrementPercent!, 50, accuracy: 1e-9)
    }

    func testIncreasingAmplitudeIsClampedToZeroDecrement() {
        let amps = [0.2, 0.2, 0.2, 0.5, 0.5, 0.5]
        let taps = amps.enumerated().map { TapEvent(time: Double($0.offset) * 0.25, amplitude: $0.element) }
        XCTAssertEqual(TapMetrics.compute(taps: taps, durationSec: 2).amplitudeDecrementPercent, 0)
    }

    func testTrimmedMeanDropsOutliers() {
        // n = 10 → trim 1 from each end.
        let amps = [0.0, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 5.0]
        let taps = amps.enumerated().map { TapEvent(time: Double($0.offset) * 0.2, amplitude: $0.element) }
        XCTAssertEqual(TapMetrics.compute(taps: taps, durationSec: 2).meanAmplitude!, 0.4, accuracy: 1e-9)
    }
}
