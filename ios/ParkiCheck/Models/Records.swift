import Foundation
import SwiftData

enum Hand: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "왼손" : "오른손" }
    var sideLabel: String { self == .left ? "왼쪽" : "오른쪽" }
}

/// One descriptive measurement shown to the user. Never a score or grade.
struct Metric: Codable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let value: Double?
    let unit: String
    let decimals: Int

    var formatted: String {
        guard let value else { return "—" }
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        return unit.isEmpty ? number : "\(number)\(unit)"
    }
}

/// Result of one recorded movement task.
@Model
final class TaskResult {
    var id: UUID
    var kindRaw: String
    var sideRaw: String?
    var startedAt: Date
    var durationSec: Double
    var metricsData: Data
    /// The task's headline value, used for the trend chart.
    var primaryValue: Double?
    var note: String

    var kind: TaskKind { TaskKind(rawValue: kindRaw) ?? .fingerTapping }
    var side: Hand? { sideRaw.flatMap(Hand.init(rawValue:)) }
    var metrics: [Metric] { (try? JSONDecoder().decode([Metric].self, from: metricsData)) ?? [] }

    init(kind: TaskKind, side: Hand?, startedAt: Date, durationSec: Double, metrics: [Metric], note: String = "") {
        id = UUID()
        kindRaw = kind.rawValue
        sideRaw = side?.rawValue
        self.startedAt = startedAt
        self.durationSec = durationSec
        metricsData = (try? JSONEncoder().encode(metrics)) ?? Data()
        primaryValue = metrics.first(where: { $0.key == kind.primaryMetricKey })?.value
        self.note = note
    }
}

/// A medication the patient takes on a schedule. Entered once; intake is then logged with one tap.
@Model
final class Medication {
    var id: UUID
    var name: String
    var dose: String
    /// Scheduled times as minutes after midnight, sorted.
    var minutesOfDay: [Int]
    var isActive: Bool
    var createdAt: Date

    init(name: String, dose: String, minutesOfDay: [Int]) {
        id = UUID()
        self.name = name
        self.dose = dose
        self.minutesOfDay = minutesOfDay.sorted()
        isActive = true
        createdAt = Date()
    }
}

/// Patient-reported medication intake. Recorded as-is; the app never infers drug effect.
@Model
final class MedicationEntry {
    var id: UUID
    var takenAt: Date
    var name: String
    var dose: String
    var medicationID: UUID?
    /// The scheduled slot this intake answers (minutes after midnight), if any.
    var scheduledMinute: Int?
    var note: String

    init(takenAt: Date, name: String, dose: String, medicationID: UUID? = nil, scheduledMinute: Int? = nil, note: String = "") {
        id = UUID()
        self.takenAt = takenAt
        self.name = name
        self.dose = dose
        self.medicationID = medicationID
        self.scheduledMinute = scheduledMinute
        self.note = note
    }
}

/// Patient-reported state, in the spirit of an ON/OFF diary. Chosen by the patient, never inferred.
enum PatientState: String, Codable, CaseIterable, Identifiable {
    case good, off, dyskinesia
    var id: String { rawValue }

    var label: String {
        switch self {
        case .good: return "괜찮아요"
        case .off: return "약효가 떨어졌어요"
        case .dyskinesia: return "몸이 저절로 움직여요"
        }
    }

    var shortLabel: String {
        switch self {
        case .good: return "괜찮음"
        case .off: return "약효 떨어짐"
        case .dyskinesia: return "이상운동"
        }
    }

    var symbol: String {
        switch self {
        case .good: return "sun.max.fill"
        case .off: return "battery.25percent"
        case .dyskinesia: return "waveform.path"
        }
    }
}

@Model
final class StateEntry {
    var id: UUID
    var recordedAt: Date
    var stateRaw: String
    var note: String

    var state: PatientState { PatientState(rawValue: stateRaw) ?? .good }

    init(recordedAt: Date, state: PatientState, note: String = "") {
        id = UUID()
        self.recordedAt = recordedAt
        stateRaw = state.rawValue
        self.note = note
    }
}

/// A patient's own words: symptoms ("넘어졌어", "손이 떨려") or a free note, with symptom tags.
@Model
final class DiaryNote {
    var id: UUID
    var recordedAt: Date
    var text: String
    var tags: [String]

    init(recordedAt: Date, text: String, tags: [String] = []) {
        id = UUID()
        self.recordedAt = recordedAt
        self.text = text
        self.tags = tags
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [TaskResult.self, Medication.self, MedicationEntry.self, StateEntry.self, DiaryNote.self]

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        // v2 store: the skeleton's TapSession store is not migrated (it never shipped).
        let config = ModelConfiguration("ParkiCheck-v2", isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: Schema(models), configurations: config)
        } catch {
            fatalError("Could not open the record store: \(error)")
        }
    }
}

extension Int {
    /// Formats minutes-after-midnight as a localized time, e.g. "오후 2:00".
    var clockLabel: String {
        var components = DateComponents()
        components.hour = self / 60
        components.minute = self % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
