import Foundation

/// Today's dose slots and their status, computed from the schedule and logged intakes.
struct DoseSlot: Identifiable, Equatable {
    enum Status: Equatable { case taken(Date), due, upcoming, missed }

    var id: String { "\(medicationID.uuidString)-\(minute)" }
    let medicationID: UUID
    let name: String
    let dose: String
    let minute: Int
    let status: Status
}

enum DoseSchedule {
    /// A dose counts as due from 30 minutes before to 2 hours after its time; after that it is missed.
    static let dueBeforeMinutes = 30
    static let missedAfterMinutes = 120

    struct MedicationInfo {
        let id: UUID
        let name: String
        let dose: String
        let minutesOfDay: [Int]
    }

    struct Intake {
        let medicationID: UUID?
        let scheduledMinute: Int?
        let takenAt: Date
    }

    static func slots(for medications: [MedicationInfo], intakes: [Intake], now: Date, calendar: Calendar = .current) -> [DoseSlot] {
        let startOfDay = calendar.startOfDay(for: now)
        let nowMinute = Int(now.timeIntervalSince(startOfDay) / 60)
        let todays = intakes.filter { calendar.isDate($0.takenAt, inSameDayAs: now) }

        return medications.flatMap { med in
            med.minutesOfDay.map { minute -> DoseSlot in
                let status: DoseSlot.Status
                if let intake = todays.first(where: { $0.medicationID == med.id && $0.scheduledMinute == minute }) {
                    status = .taken(intake.takenAt)
                } else if nowMinute > minute + missedAfterMinutes {
                    status = .missed
                } else if nowMinute >= minute - dueBeforeMinutes {
                    status = .due
                } else {
                    status = .upcoming
                }
                return DoseSlot(medicationID: med.id, name: med.name, dose: med.dose, minute: minute, status: status)
            }
        }
        .sorted { $0.minute < $1.minute }
    }

    /// The dose to surface on the home screen: the earliest due one, else the next upcoming one.
    static func next(in slots: [DoseSlot]) -> DoseSlot? {
        slots.first { $0.status == .due } ?? slots.first { $0.status == .upcoming }
    }
}

/// Seven-day summary for the home card and the clinician report. Descriptive only.
struct WeeklySummary: Equatable {
    struct StateCounts: Equatable {
        var good = 0, off = 0, dyskinesia = 0
        var total: Int { good + off + dyskinesia }
    }

    enum DayPart: String, CaseIterable {
        case morning = "오전", afternoon = "오후", evening = "저녁", night = "밤"

        static func of(hour: Int) -> DayPart {
            switch hour {
            case 5..<12: return .morning
            case 12..<18: return .afternoon
            case 18..<23: return .evening
            default: return .night
            }
        }
    }

    let scheduledDoses: Int
    let takenOnSchedule: Int
    let states: StateCounts
    /// OFF reports per part of day, to show when "wearing off" is reported most.
    let offByDayPart: [DayPart: Int]
    let tappingRateThisWeek: Double?
    let tappingRateLastWeek: Double?
    let checkDays: Int

    var adherencePercent: Int? {
        scheduledDoses > 0 ? Int((Double(takenOnSchedule) / Double(scheduledDoses) * 100).rounded()) : nil
    }

    var busiestOffPart: DayPart? {
        offByDayPart.filter { $0.value > 0 }.max { $0.value < $1.value }?.key
    }

    struct Input {
        let medications: [DoseSchedule.MedicationInfo]
        let medicationCreatedAt: [UUID: Date]
        let intakes: [DoseSchedule.Intake]
        let states: [(date: Date, state: PatientState)]
        /// (date, taps per second) of finger tapping recordings.
        let tapping: [(date: Date, rate: Double)]
        let checkDates: [Date]
    }

    static func make(_ input: Input, now: Date, calendar: Calendar = .current) -> WeeklySummary {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let lastWeekStart = calendar.date(byAdding: .day, value: -13, to: today)!
        func inThisWeek(_ d: Date) -> Bool { d >= weekStart && d <= now }

        // Count scheduled slots per day that have already passed, from when each medication was added.
        var scheduled = 0, taken = 0
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            for med in input.medications {
                let added = calendar.startOfDay(for: input.medicationCreatedAt[med.id] ?? weekStart)
                guard day >= added else { continue }
                for minute in med.minutesOfDay {
                    let slotTime = day.addingTimeInterval(TimeInterval(minute * 60))
                    guard slotTime <= now else { continue }
                    scheduled += 1
                    if input.intakes.contains(where: {
                        $0.medicationID == med.id && $0.scheduledMinute == minute && calendar.isDate($0.takenAt, inSameDayAs: day)
                    }) { taken += 1 }
                }
            }
        }

        var counts = StateCounts()
        var offParts: [DayPart: Int] = [:]
        for entry in input.states where inThisWeek(entry.date) {
            switch entry.state {
            case .good: counts.good += 1
            case .off:
                counts.off += 1
                offParts[DayPart.of(hour: calendar.component(.hour, from: entry.date)), default: 0] += 1
            case .dyskinesia: counts.dyskinesia += 1
            }
        }

        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let thisWeekRates = input.tapping.filter { inThisWeek($0.date) }.map(\.rate)
        let lastWeekRates = input.tapping.filter { $0.date >= lastWeekStart && $0.date < weekStart }.map(\.rate)
        let checkDays = Set(input.checkDates.filter(inThisWeek).map { calendar.startOfDay(for: $0) }).count

        return WeeklySummary(scheduledDoses: scheduled, takenOnSchedule: taken, states: counts, offByDayPart: offParts,
                             tappingRateThisWeek: mean(thisWeekRates), tappingRateLastWeek: mean(lastWeekRates),
                             checkDays: checkDays)
    }
}
