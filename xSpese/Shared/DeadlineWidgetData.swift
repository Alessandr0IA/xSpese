import Foundation

struct DeadlineWidgetItem: Codable, Identifiable {
    let id: Int
    let title: String
    let dueDate: Date
    let amount: String?
    let currency: String
    let priority: String
}

struct DeadlineWidgetSnapshot: Codable {
    let updatedAt: Date
    let deadlines: [DeadlineWidgetItem]
}

struct MonthlyWidgetSnapshot: Codable {
    let updatedAt: Date
    let year: Int
    let month: Int
    let total: String
    let currency: String
    let topCategory: String?
    let topCategoryTotal: String?
}

struct SyncWidgetSnapshot: Codable {
    let updatedAt: Date
    let pendingCount: Int
    let failedCount: Int
    let lastSuccessfulSync: Date?
}

private enum WidgetSharedStore {
    static let appGroupID = "group.it.alessandroiacca.xSpese"

    static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    static func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum DeadlineWidgetStore {
    private static let storageKey = "deadlineWidgetSnapshot"

    static func save(_ snapshot: DeadlineWidgetSnapshot) {
        WidgetSharedStore.save(snapshot, forKey: storageKey)
    }

    static func load() -> DeadlineWidgetSnapshot? {
        WidgetSharedStore.load(DeadlineWidgetSnapshot.self, forKey: storageKey)
    }
}

enum MonthlyWidgetStore {
    private static let storageKey = "monthlyWidgetSnapshot"

    static func save(_ snapshot: MonthlyWidgetSnapshot) {
        WidgetSharedStore.save(snapshot, forKey: storageKey)
    }

    static func load() -> MonthlyWidgetSnapshot? {
        WidgetSharedStore.load(MonthlyWidgetSnapshot.self, forKey: storageKey)
    }
}

enum SyncWidgetStore {
    private static let storageKey = "syncWidgetSnapshot"

    static func save(_ snapshot: SyncWidgetSnapshot) {
        WidgetSharedStore.save(snapshot, forKey: storageKey)
    }

    static func load() -> SyncWidgetSnapshot? {
        WidgetSharedStore.load(SyncWidgetSnapshot.self, forKey: storageKey)
    }
}
