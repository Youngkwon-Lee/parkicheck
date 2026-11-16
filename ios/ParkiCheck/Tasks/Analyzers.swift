import CoreGraphics
import Foundation

/// Turns a stream of tracker frames into descriptive metrics. Each analyzer receives exactly one
/// call per camera frame (with real timestamps), fixing the web version's repeated processing
/// of the same landmarks on every display refresh.
protocol TaskAnalyzer {
    mutating func process(_ frame: TrackerFrame)
    /// Live counter shown during recording (events so far), if the task counts events.
    var liveCount: Int? { get }
    func metrics(durationSec: Double) -> [Metric]
}

/// Shared metrics for repetitive movements (taps, open/close cycles, flips, lifts).
enum CycleMetricSet {
    static func make(events: [TapEvent], durationSec: Double, pauseThreshold: TimeInterval,
                     countLabel: String, amplitudeLabel: String, amplitudeDecimals: Int = 2) -> [Metric] {
        let m = TapMetrics.compute(taps: events, durationSec: durationSec, pauseThreshold: pauseThreshold)
        return [
            Metric(key: "count", label: countLabel, value: Double(m.tapCount), unit: "회", decimals: 0),
            Metric(key: "rate", label: "초당 횟수", value: m.tapsPerSecond, unit: "", decimals: 1),
            Metric(key: "medianInterval", label: "간격(중앙값)", value: m.medianIntervalMs, unit: "ms", decimals: 0),
            Metric(key: "intervalCV", label: "간격 변동", value: m.intervalCVPercent, unit: "%", decimals: 0),
            Metric(key: "amplitude", label: amplitudeLabel, value: m.meanAmplitude, unit: "", decimals: amplitudeDecimals),
            Metric(key: "decrement", label: "후반부 크기 감소", value: m.amplitudeDecrementPercent, unit: "%", decimals: 0),
            Metric(key: "pauses", label: "멈춤(\(pauseThreshold.formatted())초 이상)", value: Double(m.pauseCount), unit: "회", decimals: 0),
        ]
    }
}

// MARK: Hand tasks

struct FingerTappingAnalyzer: TaskAnalyzer {
    private(set) var detector = TapDetector()

    mutating func process(_ frame: TrackerFrame) {
        guard let h = frame.hand else { return }
        detector.process(HandSample(timestamp: frame.timestamp, thumbTip: h.thumbTip, indexTip: h.indexTip,
                                    wrist: h.wrist, middleMCP: h.middleMCP))
    }

    var liveCount: Int? { detector.taps.count }

    func metrics(durationSec: Double) -> [Metric] {
        CycleMetricSet.make(events: detector.taps, durationSec: durationSec, pauseThreshold: TapMetrics.pauseThreshold,
                            countLabel: "탭 횟수", amplitudeLabel: "평균 벌림 크기")
    }
}

/// Fist open/close. Unlike the web version, a cycle counts only after a full close (hysteresis),
/// so a finger dipping below the open threshold does not create an extra cycle.
struct HandMovementAnalyzer: TaskAnalyzer {
    static let openRatio = 0.72, closedRatio = 0.50, cooldown: TimeInterval = 0.28

    private(set) var events: [TapEvent] = []
    private var handSizeRef: Double?
    private var wasClosed = false
    private var lastEvent: TimeInterval = -.infinity
    private var peak = 0.0

    mutating func process(_ frame: TrackerFrame) {
        guard let h = frame.hand else { return }
        let hs = h.handSize
        guard hs > 1 else { return }
        let ref = handSizeRef.map { $0 * 0.9 + hs * 0.1 } ?? hs
        handSizeRef = ref
        let palm = CGPoint.mean(h.mcps)
        let ratios = h.tips.map { $0.distance(to: palm) / ref }
        let avg = ratios.reduce(0, +) / Double(ratios.count)
        peak = max(peak, avg)

        if ratios.allSatisfy({ $0 < Self.closedRatio }) { wasClosed = true }
        if wasClosed, ratios.allSatisfy({ $0 > Self.openRatio }), frame.timestamp - lastEvent > Self.cooldown {
            events.append(TapEvent(time: frame.timestamp, amplitude: peak))
            lastEvent = frame.timestamp
            wasClosed = false
            peak = avg
        }
    }

    var liveCount: Int? { events.count }

    func metrics(durationSec: Double) -> [Metric] {
        CycleMetricSet.make(events: events, durationSec: durationSec, pauseThreshold: 0.6,
                            countLabel: "쥐었다 편 횟수", amplitudeLabel: "평균 펴짐 크기")
    }
}

/// Palm flips, detected from the sign of the 2D cross product of wrist→index MCP and
/// wrist→little MCP. Fixes from the web version: normalized by hand size², and a deadband
/// around edge-on so jitter does not create flips. One event per half-cycle (one flip).
struct PronationAnalyzer: TaskAnalyzer {
    static let deadband = 0.08, cooldown: TimeInterval = 0.3

    private(set) var events: [TapEvent] = []
    private var sign = 0
    private var lastFlip: TimeInterval = -.infinity
    private var peak = 0.0

    mutating func process(_ frame: TrackerFrame) {
        guard let h = frame.hand else { return }
        let hs = h.handSize
        guard hs > 1 else { return }
        let v1 = CGPoint(x: h.indexMCP.x - h.wrist.x, y: h.indexMCP.y - h.wrist.y)
        let v2 = CGPoint(x: h.littleMCP.x - h.wrist.x, y: h.littleMCP.y - h.wrist.y)
        let normal = Double(v1.x * v2.y - v1.y * v2.x) / (hs * hs)
        peak = max(peak, abs(normal))
        guard abs(normal) > Self.deadband else { return }
        let newSign = normal > 0 ? 1 : -1
        if sign != 0, newSign != sign, frame.timestamp - lastFlip > Self.cooldown {
            events.append(TapEvent(time: frame.timestamp, amplitude: peak))
            lastFlip = frame.timestamp
            peak = 0
        }
        sign = newSign
    }

    var liveCount: Int? { events.count }

    func metrics(durationSec: Double) -> [Metric] {
        CycleMetricSet.make(events: events, durationSec: durationSec, pauseThreshold: 0.8,
                            countLabel: "뒤집은 횟수", amplitudeLabel: "평균 회전 크기")
    }
}

/// Tremor from wrist motion. The web version sampled at the display rate, used only vertical
/// motion, no window and no noise check; this collects one sample per frame with real
/// timestamps and analyzes both axes with `TremorSpectrum`.
struct TremorAnalyzer: TaskAnalyzer {
    private(set) var samples: [TremorSpectrum.Sample] = []
    private var handSizeRef: Double?

    mutating func process(_ frame: TrackerFrame) {
        guard let h = frame.hand else { return }
        let hs = h.handSize
        if hs > 1 { handSizeRef = handSizeRef.map { $0 * 0.9 + hs * 0.1 } ?? hs }
        samples.append(.init(t: frame.timestamp, x: Double(h.wrist.x), y: Double(h.wrist.y)))
    }

    var liveCount: Int? { nil }

    func metrics(durationSec: Double) -> [Metric] {
        let result = TremorSpectrum.analyze(samples)
        let ref = handSizeRef ?? 0
        let amplitude = (result?.amplitude).flatMap { ref > 0 ? $0 / ref * 100 : nil }
        let clear = result?.isClear ?? false
        return [
            Metric(key: "frequency", label: "주된 떨림 주기", value: clear ? result?.frequency : nil, unit: "Hz", decimals: 1),
            Metric(key: "amplitude", label: "떨림 크기(손 크기 대비)", value: amplitude, unit: "%", decimals: 1),
            Metric(key: "clarity", label: "주기 뚜렷함", value: result?.peakToMedian, unit: "배", decimals: 1),
            Metric(key: "trackedSec", label: "손이 보인 시간", value: result?.spanSec ?? 0, unit: "초", decimals: 0),
        ]
    }
}

// MARK: Body tasks

/// Toe tapping and knee lifts for one side. Fixes from the web version: the amplitude is the
/// peak lift during each cycle (the web stored the threshold constant), the baseline only
/// adapts while the joint is down, and lift is normalized by a body segment instead of the
/// image height, so distance from the camera matters less.
struct LiftCycleAnalyzer: TaskAnalyzer {
    let joint: BodyPoints.Joint
    let segment: (BodyPoints.Joint, BodyPoints.Joint)
    let liftThreshold: Double
    let cooldown: TimeInterval
    let countLabel: String

    private(set) var events: [TapEvent] = []
    private var base: Double?
    /// Segment length measured while the joint is down; the segment foreshortens during a lift.
    private var scaleRef: Double?
    private var isUp = false
    private var peak = 0.0
    private var lastEvent: TimeInterval = -.infinity

    static func toeTapping(side: Hand) -> LiftCycleAnalyzer {
        // Ankle lift relative to shank length (knee→ankle). 0.12 is an initial value to tune on device.
        LiftCycleAnalyzer(joint: side == .left ? .leftAnkle : .rightAnkle,
                          segment: side == .left ? (.leftKnee, .leftAnkle) : (.rightKnee, .rightAnkle),
                          liftThreshold: 0.12, cooldown: 0.22, countLabel: "두드린 횟수")
    }

    static func legAgility(side: Hand) -> LiftCycleAnalyzer {
        // Knee lift relative to thigh length (hip→knee). 0.25 is an initial value to tune on device.
        LiftCycleAnalyzer(joint: side == .left ? .leftKnee : .rightKnee,
                          segment: side == .left ? (.leftHip, .leftKnee) : (.rightHip, .rightKnee),
                          liftThreshold: 0.25, cooldown: 0.26, countLabel: "무릎 든 횟수")
    }

    mutating func process(_ frame: TrackerFrame) {
        guard let body = frame.body, let p = body[joint], let a = body[segment.0], let b = body[segment.1] else { return }
        let segmentLength = a.distance(to: b)
        guard segmentLength > 1 else { return }
        let y = Double(p.y)
        guard let current = base, let scale = scaleRef else { base = y; scaleRef = segmentLength; return }
        let lift = (current - y) / scale
        if !isUp {
            if lift > liftThreshold {
                isUp = true
                peak = lift
            } else {
                base = current * 0.95 + y * 0.05
                scaleRef = scale * 0.95 + segmentLength * 0.05
            }
        } else {
            peak = max(peak, lift)
            if lift < liftThreshold * 0.5 {
                isUp = false
                if frame.timestamp - lastEvent > cooldown {
                    events.append(TapEvent(time: frame.timestamp, amplitude: peak))
                    lastEvent = frame.timestamp
                }
            }
        }
    }

    var liveCount: Int? { events.count }

    func metrics(durationSec: Double) -> [Metric] {
        CycleMetricSet.make(events: events, durationSec: durationSec, pauseThreshold: 0.6,
                            countLabel: countLabel, amplitudeLabel: "평균 높이(다리 길이 대비)")
    }
}

/// Frontal standing posture. Note: a front view shows sideways lean and shoulder level,
/// not forward stooping.
struct PostureAnalyzer: TaskAnalyzer {
    private(set) var lean: [Double] = []
    private(set) var tilt: [Double] = []
    private(set) var head: [Double] = []

    mutating func process(_ frame: TrackerFrame) {
        guard let b = frame.body, let ls = b[.leftShoulder], let rs = b[.rightShoulder],
              let lh = b[.leftHip], let rh = b[.rightHip] else { return }
        let sMid = CGPoint.mid(ls, rs), hMid = CGPoint.mid(lh, rh)
        let torso = Double(hMid.y - sMid.y)
        guard torso > 20 else { return }
        lean.append(Double(abs(sMid.x - hMid.x)) / torso)
        tilt.append(Double(abs(ls.y - rs.y)) / torso)
        if let nose = b[.nose] { head.append(max(0, Double(sMid.y - nose.y) / torso)) }
    }

    var liveCount: Int? { nil }

    func metrics(durationSec: Double) -> [Metric] {
        [
            Metric(key: "lateralLean", label: "몸통 옆기울기(몸통 길이 대비)", value: Stats.trimmedMean(lean).map { $0 * 100 }, unit: "%", decimals: 1),
            Metric(key: "shoulderTilt", label: "어깨 높이 차이", value: Stats.mean(tilt).map { $0 * 100 }, unit: "%", decimals: 1),
            Metric(key: "headHeight", label: "어깨 위 머리 높이", value: Stats.mean(head).map { $0 * 100 }, unit: "%", decimals: 0),
            Metric(key: "frames", label: "분석한 프레임", value: Double(lean.count), unit: "개", decimals: 0),
        ]
    }
}

/// Walking past the camera. Steps from ankle lifts (peak captured per step), arm swing as the
/// 5th–95th percentile range of wrist position relative to the shoulder over the whole walk.
struct GaitAnalyzer: TaskAnalyzer {
    private var left = LiftCycleAnalyzer(joint: .leftAnkle, segment: (.leftKnee, .leftAnkle), liftThreshold: 0.08, cooldown: 0.28, countLabel: "")
    private var right = LiftCycleAnalyzer(joint: .rightAnkle, segment: (.rightKnee, .rightAnkle), liftThreshold: 0.08, cooldown: 0.28, countLabel: "")
    private(set) var leftArm: [Double] = []
    private(set) var rightArm: [Double] = []

    mutating func process(_ frame: TrackerFrame) {
        left.process(frame)
        right.process(frame)
        guard let b = frame.body, let ls = b[.leftShoulder], let rs = b[.rightShoulder] else { return }
        let width = ls.distance(to: rs)
        guard width > 10 else { return }
        if let lw = b[.leftWrist] { leftArm.append(Double(lw.x - ls.x) / width) }
        if let rw = b[.rightWrist] { rightArm.append(Double(rw.x - rs.x) / width) }
    }

    var liveCount: Int? { left.events.count + right.events.count }

    func metrics(durationSec: Double) -> [Metric] {
        let steps = (left.events + right.events).sorted { $0.time < $1.time }
        let l = left.events.count, r = right.events.count
        let intervals = zip(steps.dropFirst(), steps).map { $0.time - $1.time }
        let swingL = Stats.percentileRange(leftArm), swingR = Stats.percentileRange(rightArm)
        var armAsym: Double?
        if let a = swingL, let b = swingR, max(a, b) > 0 { armAsym = abs(a - b) / max(a, b) * 100 }
        return [
            Metric(key: "steps", label: "걸음 수", value: Double(steps.count), unit: "걸음", decimals: 0),
            Metric(key: "cadence", label: "분당 걸음 수", value: durationSec > 0 ? Double(steps.count) / durationSec * 60 : nil, unit: "", decimals: 0),
            Metric(key: "stepCV", label: "걸음 간격 변동", value: intervals.count >= 3 ? Stats.cv(intervals) : nil, unit: "%", decimals: 0),
            Metric(key: "stepAsymmetry", label: "좌우 걸음 수 차이", value: max(l, r) > 0 ? Double(abs(l - r)) / Double(max(l, r)) * 100 : nil, unit: "%", decimals: 0),
            Metric(key: "armSwingAsymmetry", label: "좌우 팔 흔들림 차이", value: armAsym, unit: "%", decimals: 0),
        ]
    }
}

// MARK: Face

/// Blinks and facial movement. The blink threshold adapts to each person's open-eye level
/// measured in the first seconds (the web used a fixed threshold in a distorted coordinate
/// space). A smile prompt appears mid-recording; smile size is measured in that window.
struct FaceAnalyzer: TaskAnalyzer {
    static let calibrationSec: TimeInterval = 3
    static let smileWindow: ClosedRange<TimeInterval> = 6...11

    private var start: TimeInterval?
    private var openness: [Double] = []
    private var baseline: Double?
    private var inBlink = false
    private var lastBlink: TimeInterval = -.infinity
    private(set) var blinks = 0
    private(set) var mouth: [Double] = []
    private(set) var brow: [Double] = []
    private var neutralWidth: [Double] = []
    private var smileWidth: [Double] = []

    mutating func process(_ frame: TrackerFrame) {
        guard let f = frame.face, f.boundingBox.height > 20 else { return }
        let t0 = start ?? frame.timestamp
        start = t0
        let elapsed = frame.timestamp - t0
        let faceH = Double(f.boundingBox.height)

        let eye = (f.leftEye.aspect + f.rightEye.aspect) / 2
        if elapsed < Self.calibrationSec {
            openness.append(eye)
        } else {
            if baseline == nil { baseline = Stats.median(openness) }
            if let base = baseline, base > 0 {
                if !inBlink, eye < base * 0.55 {
                    inBlink = true
                } else if inBlink, eye > base * 0.75 {
                    inBlink = false
                    if frame.timestamp - lastBlink > 0.3 { blinks += 1; lastBlink = frame.timestamp }
                }
            }
        }

        mouth.append(f.innerLips.height / faceH)
        let eyeY = Double((CGPoint.mean(f.leftEye).y + CGPoint.mean(f.rightEye).y) / 2)
        let browY = Double((CGPoint.mean(f.leftBrow).y + CGPoint.mean(f.rightBrow).y) / 2)
        brow.append(max(0, eyeY - browY) / faceH)

        let width = Double((f.outerLips.map(\.x).max() ?? 0) - (f.outerLips.map(\.x).min() ?? 0)) / Double(f.boundingBox.width)
        if elapsed < Self.smileWindow.lowerBound - 1 { neutralWidth.append(width) }
        if Self.smileWindow.contains(elapsed) { smileWidth.append(width) }
    }

    var liveCount: Int? { nil }

    func metrics(durationSec: Double) -> [Metric] {
        let blinkSec = max(durationSec - Self.calibrationSec, 1)
        var smile: Double?
        if let neutral = Stats.median(neutralWidth), let peak = Stats.percentile(smileWidth, 0.9), neutral > 0 {
            smile = max(0, (peak / neutral - 1) * 100)
        }
        let variability = [Stats.sd(mouth), Stats.sd(brow)].compactMap { $0 }
        return [
            Metric(key: "blinks", label: "눈 깜빡임", value: Double(blinks), unit: "회", decimals: 0),
            Metric(key: "blinksPerMin", label: "분당 눈 깜빡임", value: Double(blinks) / blinkSec * 60, unit: "", decimals: 0),
            Metric(key: "expressionVariability", label: "얼굴 움직임 변화량", value: variability.isEmpty ? nil : variability.reduce(0, +) / Double(variability.count) * 1000, unit: "", decimals: 1),
            Metric(key: "smileWidening", label: "웃을 때 입 너비 증가", value: smile, unit: "%", decimals: 0),
        ]
    }
}

// MARK: Stats

enum Stats {
    static func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    static func sd(_ v: [Double]) -> Double? {
        guard let m = mean(v), v.count >= 2 else { return nil }
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    }

    static func cv(_ v: [Double]) -> Double? {
        guard let m = mean(v), m > 0, let s = sd(v) else { return nil }
        return s / m * 100
    }

    static func median(_ v: [Double]) -> Double? { percentile(v, 0.5) }

    static func percentile(_ v: [Double], _ p: Double) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        let pos = p * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    static func percentileRange(_ v: [Double]) -> Double? {
        guard v.count >= 10, let lo = percentile(v, 0.05), let hi = percentile(v, 0.95) else { return nil }
        return hi - lo
    }

    static func trimmedMean(_ v: [Double]) -> Double? {
        guard v.count >= 5 else { return mean(v) }
        let s = v.sorted(), trim = max(1, v.count / 10)
        return mean(Array(s[trim..<(s.count - trim)]))
    }
}
