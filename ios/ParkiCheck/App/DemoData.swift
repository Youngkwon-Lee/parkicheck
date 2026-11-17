#if DEBUG
import Foundation
import SwiftData

/// Sample week for App Store screenshots. Debug builds only, launched with `-seedDemo`.
enum DemoData {
    @MainActor
    static func seedIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo") else { return }
        let context = container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Medication>())) ?? 0) == 0 else { return }
        let cal = Calendar.current
        let madopar = Medication(name: "마도파", dose: "1정", minutesOfDay: [8 * 60, 12 * 60, 18 * 60])
        let azilect = Medication(name: "아질렉트", dose: "1정", minutesOfDay: [8 * 60])
        madopar.createdAt = cal.date(byAdding: .day, value: -30, to: Date())!
        azilect.createdAt = madopar.createdAt
        context.insert(madopar)
        context.insert(azilect)
        let today = cal.startOfDay(for: Date())
        let nowMinute = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        for day in 0..<7 {
            let base = cal.date(byAdding: .day, value: -day, to: today)!
            for med in [madopar, azilect] {
                for minute in med.minutesOfDay where !(day == 0 && minute > nowMinute) && !(day == 3 && minute == 18 * 60) {
                    let taken = base.addingTimeInterval(TimeInterval((minute + (day * 7) % 20) * 60))
                    context.insert(MedicationEntry(takenAt: taken, name: med.name, dose: med.dose, medicationID: med.id, scheduledMinute: minute))
                }
            }
            let states: [(Int, PatientState)] = [(9 * 60 + 30, .good), (11 * 60 + 40, day % 2 == 0 ? .off : .good), (17 * 60 + 30, .off), (20 * 60, day % 3 == 0 ? .dyskinesia : .good)]
            for (minute, state) in states where !(day == 0 && minute > nowMinute) {
                context.insert(StateEntry(recordedAt: base.addingTimeInterval(TimeInterval(minute * 60)), state: state))
            }
            for (side, offset) in [(Hand.right, 0.0), (Hand.left, -0.6)] where day % 2 == 0 || day == 0 {
                let rate = 3.4 + offset + Double((day * 13) % 5) * 0.12
                context.insert(TaskResult(kind: .fingerTapping, side: side, startedAt: base.addingTimeInterval(7.5 * 3600), durationSec: 10, metrics: [
                    Metric(key: "count", label: "탭 횟수", value: (rate * 10).rounded(), unit: "회", decimals: 0),
                    Metric(key: "rate", label: "초당 횟수", value: rate, unit: "회/초", decimals: 1),
                ]))
            }
        }
        context.insert(DiaryNote(recordedAt: cal.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(19 * 3600), text: "저녁에 손이 떨려서 숟가락 들기가 힘들었어", tags: ["떨림"]))
        context.insert(DiaryNote(recordedAt: cal.date(byAdding: .day, value: -4, to: today)!.addingTimeInterval(7 * 3600), text: "잠을 못 잤어", tags: ["수면"]))
        try? context.save()
    }
}
#endif
