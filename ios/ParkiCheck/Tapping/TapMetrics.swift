import Foundation

/// Descriptive measurements of one tapping recording.
///
/// Deliberately no score, severity grade, or clinical label: the app records
/// observations for self-tracking and sharing with a clinician.
struct TapMetrics: Codable, Equatable {
    let tapCount: Int
    let durationSec: Double
    let tapsPerSecond: Double
    let medianIntervalMs: Double?
    /// Coefficient of variation of inter-tap intervals, percent.
    let intervalCVPercent: Double?
    /// Trimmed mean opening (ratio to hand size).
    let meanAmplitude: Double?
    /// How much smaller the second half's openings are than the first half's, percent (0 if not smaller).
    let amplitudeDecrementPercent: Double?
    /// Gaps between taps longer than the pause threshold.
    let pauseCount: Int

    static let pauseThreshold: TimeInterval = 0.6

    static func compute(taps: [TapEvent], durationSec: Double, pauseThreshold: TimeInterval = pauseThreshold) -> TapMetrics {
        let n = taps.count
        let intervals = zip(taps.dropFirst(), taps).map { $0.time - $1.time }

        var cv: Double?
        if intervals.count >= 2 {
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
            cv = mean > 0 ? variance.squareRoot() / mean * 100 : 0
        }

        var meanAmplitude: Double?
        if n > 0 {
            let sorted = taps.map(\.amplitude).sorted()
            let trim = max(1, n / 10)
            let kept = n >= 4 ? Array(sorted[trim..<(n - trim)]) : sorted
            meanAmplitude = kept.reduce(0, +) / Double(kept.count)
        }

        var decrement: Double?
        if n >= 6 {
            let half = n / 2
            let first = taps.prefix(half).map(\.amplitude).reduce(0, +) / Double(half)
            let last = taps.suffix(half).map(\.amplitude).reduce(0, +) / Double(half)
            decrement = first > 0 ? max(0, (1 - last / first) * 100) : nil
        }

        return TapMetrics(
            tapCount: n,
            durationSec: durationSec,
            tapsPerSecond: durationSec > 0 ? Double(n) / durationSec : 0,
            medianIntervalMs: median(intervals).map { $0 * 1000 },
            intervalCVPercent: cv,
            meanAmplitude: meanAmplitude,
            amplitudeDecrementPercent: decrement,
            pauseCount: intervals.filter { $0 > pauseThreshold }.count
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
