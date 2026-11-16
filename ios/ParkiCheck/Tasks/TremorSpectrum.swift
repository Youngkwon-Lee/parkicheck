import Foundation

/// Dominant oscillation in wrist motion between 3 and 12 Hz.
///
/// Steps: resample both axes onto a uniform 30 Hz grid by linear interpolation (camera frame
/// times are not perfectly regular), remove a linear trend, apply a Hann window, then sum the
/// power of the x and y spectra. The amplitude is the single-sided peak amplitude corrected for
/// the window, in input units. `isClear` requires the peak power to stand well above the band's
/// median power, so random jitter is not reported as a tremor frequency.
enum TremorSpectrum {
    struct Sample: Equatable {
        let t: TimeInterval
        let x: Double
        let y: Double
    }

    struct Result: Equatable {
        let frequency: Double
        let amplitude: Double
        let peakToMedian: Double
        let spanSec: Double
        var isClear: Bool { peakToMedian >= clarityThreshold }
    }

    static let sampleRate = 30.0
    static let band = 3.0...12.0
    /// For pure noise the largest of ~130 band bins is typically ~5x the median, so 10x is required.
    /// Initial value; tune against recordings.
    static let clarityThreshold = 10.0
    static let minimumSpanSec = 4.0

    static func analyze(_ samples: [Sample]) -> Result? {
        let sorted = samples.sorted { $0.t < $1.t }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let span = last.t - first.t
        guard span >= minimumSpanSec, sorted.count >= Int(span * 10) else { return nil }

        let n = Int(span * sampleRate)
        var xs = [Double](), ys = [Double]()
        xs.reserveCapacity(n); ys.reserveCapacity(n)
        var j = 0
        for i in 0..<n {
            let t = first.t + Double(i) / sampleRate
            while j < sorted.count - 2, sorted[j + 1].t < t { j += 1 }
            let a = sorted[j], b = sorted[j + 1]
            let w = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
            xs.append(a.x + (b.x - a.x) * w)
            ys.append(a.y + (b.y - a.y) * w)
        }

        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1)) }
        let windowSum = window.reduce(0, +)
        let px = prepared(xs, window), py = prepared(ys, window)

        let resolution = sampleRate / Double(n)
        let kMin = Int((band.lowerBound / resolution).rounded(.up))
        let kMax = min(Int((band.upperBound / resolution).rounded(.down)), n / 2)
        guard kMax > kMin else { return nil }

        var powers: [(k: Int, power: Double)] = []
        for k in kMin...kMax {
            powers.append((k, magnitudeSquared(px, k) + magnitudeSquared(py, k)))
        }
        guard let peak = powers.max(by: { $0.power < $1.power }) else { return nil }
        let median = Stats.median(powers.map(\.power)) ?? 0
        let amplitude = 2 * peak.power.squareRoot() / windowSum
        return Result(frequency: Double(peak.k) * resolution, amplitude: amplitude,
                      peakToMedian: median > 0 ? peak.power / median : 0, spanSec: span)
    }

    private static func prepared(_ v: [Double], _ window: [Double]) -> [Double] {
        let n = Double(v.count)
        let tMean = (n - 1) / 2
        let vMean = v.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (i, value) in v.enumerated() {
            num += (Double(i) - tMean) * (value - vMean)
            den += (Double(i) - tMean) * (Double(i) - tMean)
        }
        let slope = den > 0 ? num / den : 0
        return v.enumerated().map { i, value in (value - vMean - slope * (Double(i) - tMean)) * window[i] }
    }

    private static func magnitudeSquared(_ s: [Double], _ k: Int) -> Double {
        var re = 0.0, im = 0.0
        let step = -2 * Double.pi * Double(k) / Double(s.count)
        for (i, value) in s.enumerated() {
            re += value * cos(step * Double(i))
            im += value * sin(step * Double(i))
        }
        return re * re + im * im
    }
}
