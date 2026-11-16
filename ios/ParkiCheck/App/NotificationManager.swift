import Foundation
import SwiftData
import UserNotifications

/// Local medication reminders with one-tap actions. Nothing leaves the device.
///
/// Each scheduled dose gets a repeating reminder with "먹었어요" / "10분 뒤 다시".
/// An hour after each dose, a state check offers the three patient-reported states as actions,
/// so both can be logged straight from the lock screen without opening the app.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    enum ID {
        static let doseCategory = "DOSE"
        static let stateCategory = "STATE"
        static let taken = "TAKEN"
        static let snooze = "SNOOZE"
        static let statePrefix = "STATE_"
        static let dosePrefix = "dose-"
        static let checkPrefix = "check-"
    }

    static let stateCheckDelayMinutes = 60
    static let snoozeMinutes = 10

    private let center = UNUserNotificationCenter.current()
    private var container: ModelContainer?

    func configure(container: ModelContainer) {
        self.container = container
        center.delegate = self
        let taken = UNNotificationAction(identifier: ID.taken, title: "먹었어요")
        let snooze = UNNotificationAction(identifier: ID.snooze, title: "\(Self.snoozeMinutes)분 뒤 다시")
        let stateActions = PatientState.allCases.map {
            UNNotificationAction(identifier: ID.statePrefix + $0.rawValue, title: $0.label)
        }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ID.doseCategory, actions: [taken, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: ID.stateCategory, actions: stateActions, intentIdentifiers: []),
        ])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all medication reminders with ones matching the active schedule.
    func reschedule(_ medications: [Medication]) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix(ID.dosePrefix) || $0.hasPrefix(ID.checkPrefix)
        })
        guard await authorizationStatus() == .authorized else { return }

        for med in medications where med.isActive {
            for minute in med.minutesOfDay {
                let dose = UNMutableNotificationContent()
                dose.title = "\(med.name) 드실 시간이에요"
                dose.body = med.dose.isEmpty ? "\(minute.clockLabel) 복약" : "\(med.dose) · \(minute.clockLabel) 복약"
                dose.sound = .default
                dose.categoryIdentifier = ID.doseCategory
                dose.userInfo = ["medicationID": med.id.uuidString, "minute": minute]
                try? await center.add(UNNotificationRequest(
                    identifier: "\(ID.dosePrefix)\(med.id.uuidString)-\(minute)",
                    content: dose, trigger: Self.dailyTrigger(minute: minute)))

                let check = UNMutableNotificationContent()
                check.title = "지금 몸 상태는 어떠세요?"
                check.body = "길게 눌러 바로 기록할 수 있어요."
                check.sound = .default
                check.categoryIdentifier = ID.stateCategory
                try? await center.add(UNNotificationRequest(
                    identifier: "\(ID.checkPrefix)\(med.id.uuidString)-\(minute)",
                    content: check, trigger: Self.dailyTrigger(minute: (minute + Self.stateCheckDelayMinutes) % (24 * 60))))
            }
        }
    }

    private static func dailyTrigger(minute: Int) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let info = content.userInfo
        let medicationID = (info["medicationID"] as? String).flatMap(UUID.init(uuidString:))
        let minute = info["minute"] as? Int
        await MainActor.run {
            self.handle(action: action, medicationID: medicationID, minute: minute, content: content)
        }
    }

    private func handle(action: String, medicationID: UUID?, minute: Int?, content: UNNotificationContent) {
        guard let context = container?.mainContext else { return }
        switch action {
        case ID.taken:
            Self.logIntake(medicationID: medicationID, minute: minute, in: context)
        case ID.snooze:
            let again = (content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(Self.snoozeMinutes * 60), repeats: false)
            center.add(UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: again, trigger: trigger))
        case let id where id.hasPrefix(ID.statePrefix):
            if let state = PatientState(rawValue: String(id.dropFirst(ID.statePrefix.count))) {
                context.insert(StateEntry(recordedAt: Date(), state: state))
                try? context.save()
            }
        default:
            break
        }
    }

    /// Logs an intake for a scheduled dose. Shared by the notification action and the in-app button.
    static func logIntake(medicationID: UUID?, minute: Int?, at date: Date = Date(), in context: ModelContext) {
        guard let medicationID else { return }
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID })
        guard let med = try? context.fetch(descriptor).first else { return }
        context.insert(MedicationEntry(takenAt: date, name: med.name, dose: med.dose, medicationID: med.id, scheduledMinute: minute))
        try? context.save()
    }
}
