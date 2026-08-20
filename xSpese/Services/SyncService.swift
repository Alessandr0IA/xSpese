import Foundation
import OSLog
import SwiftData

@MainActor
final class SyncService {
    static let shared = SyncService()

    private(set) var isSyncing = false

    private init() {}

    func syncPendingTransactions(in context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.createdAt)]
        )
        guard let allTransactions = try? context.fetch(descriptor) else { return }

        let pendingTransactions = allTransactions.filter { $0.syncStatus != .synced }
        for transaction in pendingTransactions {
            await sync(transaction, in: context, refreshMonthlyWidget: false)
        }
        if !pendingTransactions.isEmpty {
            await ExpenseWidgetCacheService.refreshMonthlyReport()
        }
    }

    func sync(_ transaction: Transaction, in context: ModelContext, refreshMonthlyWidget: Bool = true) async {
        guard transaction.syncStatus != .synced else { return }
        defer { ExpenseWidgetCacheService.updateSyncStatus() }

        do {
            let client = try makeClient()
            transaction.syncStatus = .syncing
            transaction.lastSyncAttempt = .now
            transaction.syncAttemptCount += 1
            transaction.syncError = nil
            transaction.updatedAt = .now
            try context.save()

            let response = try await client.createMovement(from: transaction)
            transaction.syncStatus = .synced
            transaction.serverId = response.transactionUUID
            transaction.syncError = nil
            transaction.updatedAt = .now
            try context.save()
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSuccessfulSyncTimestamp")
            if refreshMonthlyWidget {
                await ExpenseWidgetCacheService.refreshMonthlyReport()
            }
            Logger.sync.info("Transazione sincronizzata: \(transaction.id, privacy: .public)")
        } catch {
            transaction.syncStatus = .failed
            transaction.syncError = error.localizedDescription
            transaction.updatedAt = .now
            try? context.save()
            Logger.sync.error("Sync fallita per \(transaction.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await NotificationService.notifyRepeatedSyncFailure(for: transaction)
        }
    }

    func configuredClient() throws -> APIClient {
        try makeClient()
    }

    private func makeClient() throws -> APIClient {
        let defaults = UserDefaults.standard
        let rawURL = (defaults.string(forKey: "serverBaseURL") ?? "http://100.112.193.68:3030")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainService.loadAPIToken()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedUserID = defaults.integer(forKey: "serverUserID")
        let userID = storedUserID > 0 ? storedUserID : 1

        guard let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !token.isEmpty,
              userID > 0 else {
            throw APIError.invalidConfiguration
        }
        return APIClient(baseURL: url, token: token, userID: userID)
    }
}

extension UserDefaults {
    var automaticSyncEnabled: Bool {
        object(forKey: "automaticSyncEnabled") == nil || bool(forKey: "automaticSyncEnabled")
    }

    var defaultCurrency: String {
        let value = string(forKey: "defaultCurrency")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        return value.count == 3 ? value : "EUR"
    }
}

private extension Logger {
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xSpese", category: "Sync")
}
