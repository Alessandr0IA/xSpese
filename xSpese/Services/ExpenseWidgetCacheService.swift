import Foundation
import SwiftData
import WidgetKit

enum ExpenseWidgetCacheService {
    static func store(_ report: MonthlyReport) {
        let current = Calendar.current.dateComponents([.year, .month], from: .now)
        guard report.year == current.year, report.month == current.month else { return }

        let topCategory = report.categories.max { $0.total.value < $1.total.value }
        MonthlyWidgetStore.save(
            MonthlyWidgetSnapshot(
                updatedAt: .now,
                year: report.year,
                month: report.month,
                total: decimalString(report.total.value),
                currency: UserDefaults.standard.defaultCurrency,
                topCategory: topCategory?.category,
                topCategoryTotal: topCategory.map { decimalString($0.total.value) }
            )
        )
        reloadRelevantWidgets()
    }

    @MainActor
    static func updateSyncStatus() {
        let context = PersistenceController.shared.container.mainContext
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let failedCount = transactions.filter { $0.syncStatus == .failed }.count
        let pendingCount = transactions.filter { $0.syncStatus != .synced }.count
        let lastSyncTimestamp = UserDefaults.standard.double(forKey: "lastSuccessfulSyncTimestamp")

        SyncWidgetStore.save(
            SyncWidgetSnapshot(
                updatedAt: .now,
                pendingCount: pendingCount,
                failedCount: failedCount,
                lastSuccessfulSync: lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil
            )
        )
        reloadRelevantWidgets()
    }

    @MainActor
    static func refreshMonthlyReport() async {
        let components = Calendar.current.dateComponents([.year, .month], from: .now)
        do {
            let report = try await SyncService.shared.configuredClient().fetchMonthlyReport(
                year: components.year ?? 0,
                month: components.month ?? 0
            )
            store(report)
        } catch {
            // Mantiene l'ultimo report valido quando il Raspberry non è raggiungibile.
        }
    }

    @MainActor
    static func refreshAll() async {
        updateSyncStatus()
        await refreshMonthlyReport()
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func reloadRelevantWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "xSpeseMonthly")
        WidgetCenter.shared.reloadTimelines(ofKind: "xSpeseSync")
        WidgetCenter.shared.reloadTimelines(ofKind: "xSpeseOverview")
    }
}
