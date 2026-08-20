import Foundation
import UserNotifications

enum NotificationService {
    private static let deadlinePrefix = "deadline-reminder-"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func notifyRepeatedSyncFailure(for transaction: Transaction) async {
        guard UserDefaults.standard.bool(forKey: "syncFailureNotificationsEnabled"),
              transaction.syncAttemptCount >= 3,
              transaction.syncAttemptCount.isMultiple(of: 3) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Spesa non sincronizzata"
        content.body = "La spesa presso \(transaction.merchant) è al tentativo \(transaction.syncAttemptCount). Apri xSpese per riprovare."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sync-failure-\(transaction.id.uuidString)-\(transaction.syncAttemptCount)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func scheduleDeadlineReminders(for deadlines: [DeadlineDTO]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await removeDeadlineReminders()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        var scheduledCount = 0

        for deadline in deadlines where deadline.isOpen {
            guard let dueDate = deadline.dueDateValue else { continue }
            for days in (deadline.reminderDays ?? []).sorted() {
                guard scheduledCount < 60,
                      let reminderDay = calendar.date(byAdding: .day, value: -days, to: dueDate) else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
                components.hour = 9
                components.minute = 0
                components.timeZone = TimeZone(identifier: "Europe/Rome")
                guard let notificationDate = calendar.date(from: components), notificationDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = days == 0 ? "Scadenza di oggi" : "Scadenza in arrivo"
                content.body = reminderBody(for: deadline, daysBefore: days)
                content.sound = .default
                content.userInfo = ["deadline_id": deadline.id]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(deadlinePrefix)\(deadline.id)-\(days)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
                scheduledCount += 1
            }
        }
    }

    static func removeDeadlineReminders() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(deadlinePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func reminderBody(for deadline: DeadlineDTO, daysBefore: Int) -> String {
        let timing: String
        switch daysBefore {
        case 0: timing = "scade oggi"
        case 1: timing = "scade domani"
        default: timing = "scade tra \(daysBefore) giorni"
        }
        if let amount = deadline.amount?.value {
            let formatted = amount.formatted(.currency(code: deadline.currency ?? "EUR"))
            return "\(deadline.title) \(timing): \(formatted)."
        }
        return "\(deadline.title) \(timing)."
    }
}
