import BackgroundTasks
import Foundation

@MainActor
enum BackgroundSyncService {
    static let identifier = "it.alessandroiacca.xSpese.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        guard UserDefaults.standard.automaticSyncEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let operation = Task { @MainActor in
            let context = PersistenceController.shared.container.mainContext
            await SyncService.shared.syncPendingTransactions(in: context)
            await ExpenseWidgetCacheService.refreshAll()
            await DeadlineWidgetCacheService.refresh()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { operation.cancel() }
    }
}
