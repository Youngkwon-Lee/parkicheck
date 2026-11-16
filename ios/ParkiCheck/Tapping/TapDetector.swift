import CoreGraphics
import Foundation

/// One frame of hand landmarks in a common pixel space (not Vision's normalized space,
/// so that x/y distances are comparable regardless of image aspect ratio).
struct HandSample: Equatable {
    let timestamp: TimeInterval
    let thumbTip: CGPoint
    let indexTip: CGPoint
    let wrist: CGPoint
    let middleMCP: CGPoint
}

struct TapEvent: Codable, Equatable {
    /// Seconds, same clock as `HandSample.timestamp`.
    let time: TimeInterval
    /// Peak thumb–index opening since the previous tap, as a ratio of hand size (wrist → middle MCP).
    let amplitude: Double
}

/// Detects thumb–index closures from a stream of hand samples.
///
/// Ported from the web ParkiCheck finger-tapping detector, with two changes:
/// distances are normalized by hand size instead of image size, and closure uses
/// hysteresis (close/open thresholds) instead of a single threshold.
struct TapDetector {
    struct Config {
        var closeRatio: Double = 0.25
        var openRatio: Double = 0.35
        var cooldown: TimeInterval = 0.14
        var minHandSize: Double = 1e-3
    }

    let config: Config
    private(set) var taps: [TapEvent] = []
    private var isClosed = false
    private var lastTapTime: TimeInterval = -.infinity
    private var peakOpening = 0.0
    private var handSizeRef: Double?
    /// Most recent thumb–index opening ratio, for debugging and threshold tuning.
    private(set) var lastRatio: Double?

    init(config: Config = Config()) {
        self.config = config
    }

    @discardableResult
    mutating func process(_ sample: HandSample) -> TapEvent? {
        let handSize = Self.distance(sample.wrist, sample.middleMCP)
        guard handSize > config.minHandSize else { return nil }
        let reference = handSizeRef.map { $0 * 0.9 + handSize * 0.1 } ?? handSize
        handSizeRef = reference

        let ratio = Self.distance(sample.thumbTip, sample.indexTip) / reference
        lastRatio = ratio
        peakOpening = max(peakOpening, ratio)

        if isClosed {
            if ratio > config.openRatio { isClosed = false }
            return nil
        }
        guard ratio < config.closeRatio else { return nil }
        isClosed = true
        guard sample.timestamp - lastTapTime > config.cooldown else { return nil }

        let tap = TapEvent(time: sample.timestamp, amplitude: peakOpening)
        taps.append(tap)
        lastTapTime = sample.timestamp
        peakOpening = ratio
        return tap
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }
}
