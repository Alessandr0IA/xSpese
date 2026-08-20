import Foundation
import WidgetKit

enum DeadlineWidgetCacheService {
    static func store(_ deadlines: [DeadlineDTO]) {
        let items = deadlines
            .filter(\.isOpen)
            .compactMap { deadline -> DeadlineWidgetItem? in
                guard let dueDate = deadline.dueDateValue else { return nil }
                return DeadlineWidgetItem(
                    id: deadline.id,
                    title: deadline.title,
                    dueDate: dueDate,
                    amount: deadline.amount.map { NSDecimalNumber(decimal: $0.value).stringValue },
                    currency: deadline.currency ?? "EUR",
                    priority: deadline.priority ?? "normale"
                )
            }
            .sorted { $0.dueDate < $1.dueDate }

        DeadlineWidgetStore.save(DeadlineWidgetSnapshot(updatedAt: .now, deadlines: items))
        WidgetCenter.shared.reloadTimelines(ofKind: "xSpeseDeadlines")
    }

    @MainActor
    static func refresh() async {
        do {
            let deadlines = try await SyncService.shared.configuredClient().fetchDeadlines(status: .open)
            store(deadlines)
        } catch {
            // Mantiene l'ultima copia valida quando il Raspberry non è raggiungibile.
        }
    }
}
