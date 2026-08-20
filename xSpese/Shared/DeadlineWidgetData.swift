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

enum WidgetSharedStore {
    private static let originalAppGroupID = "group.it.alessandroiacca.xSpese"

    // SideStore rimappa gli App Group aggiungendo il Team ID del certificato
    // personale e salva gli identificatori effettivi in ALTAppGroups.
    static var appGroupID: String {
        let signedGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return signedGroups.first {
            $0 == originalAppGroupID || $0.hasPrefix(originalAppGroupID + ".")
        } ?? originalAppGroupID
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }

        if let fileURL = fileURL(forKey: key) {
            try? data.write(to: fileURL, options: .atomic)
        }

        // Mantiene la compatibilità con le installazioni precedenti.
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(data, forKey: key)
        }
    }

    static func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        let data = fileURL(forKey: key).flatMap { try? Data(contentsOf: $0) }
            ?? UserDefaults(suiteName: appGroupID)?.data(forKey: key)
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func fileURL(forKey key: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("xspese-\(key).json", isDirectory: false)
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
