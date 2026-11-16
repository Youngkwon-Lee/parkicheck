import Foundation
import SwiftData

enum Hand: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "왼손" : "오른손" }
}

@Model
final class TapSession {
    var id: UUID
    var startedAt: Date
    var handRaw: String
    var durationSec: Double
    var tapCount: Int
    var tapsPerSecond: Double
    var medianIntervalMs: Double?
    var intervalCVPercent: Double?
    var meanAmplitude: Double?
    var amplitudeDecrementPercent: Double?
    var pauseCount: Int
    var note: String

    var hand: Hand { Hand(rawValue: handRaw) ?? .right }

    init(startedAt: Date, hand: Hand, metrics: TapMetrics, note: String = "") {
        id = UUID()
        self.startedAt = startedAt
        handRaw = hand.rawValue
        durationSec = metrics.durationSec
        tapCount = metrics.tapCount
        tapsPerSecond = metrics.tapsPerSecond
        medianIntervalMs = metrics.medianIntervalMs
        intervalCVPercent = metrics.intervalCVPercent
        meanAmplitude = metrics.meanAmplitude
        amplitudeDecrementPercent = metrics.amplitudeDecrementPercent
        pauseCount = metrics.pauseCount
        self.note = note
    }
}

/// Patient-reported medication intake. Recorded as-is; the app never infers drug effect or ON/OFF state.
@Model
final class MedicationEntry {
    var id: UUID
    var takenAt: Date
    var name: String
    var dose: String
    var note: String

    init(takenAt: Date, name: String, dose: String, note: String = "") {
        id = UUID()
        self.takenAt = takenAt
        self.name = name
        self.dose = dose
        self.note = note
    }
}
