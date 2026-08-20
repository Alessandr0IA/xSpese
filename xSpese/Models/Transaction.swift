import Foundation
import SwiftData

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var currency: String
    var merchant: String
    var transactionDate: Date
    var paymentMethod: String?
    var category: String?
    var categoryID: Int?
    var note: String?
    var userID: Int?
    var sourceRawValue: String
    var syncStatusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var lastSyncAttempt: Date?
    var syncError: String?
    var serverId: String?
    var syncAttemptCount: Int = 0

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRawValue) ?? .shortcut }
        set { sourceRawValue = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRawValue) ?? .pending }
        set { syncStatusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String = "EUR",
        merchant: String,
        transactionDate: Date,
        paymentMethod: String? = nil,
        category: String? = nil,
        categoryID: Int? = nil,
        note: String? = nil,
        userID: Int? = nil,
        source: TransactionSource = .shortcut,
        syncStatus: SyncStatus = .pending,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.transactionDate = transactionDate
        self.paymentMethod = paymentMethod
        self.category = category
        self.categoryID = categoryID
        self.note = note
        self.userID = userID
        self.sourceRawValue = source.rawValue
        self.syncStatusRawValue = syncStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncAttempt = nil
        self.syncError = nil
        self.serverId = nil
        self.syncAttemptCount = 0
    }
}
