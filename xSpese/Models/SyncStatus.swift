import Foundation

enum SyncStatus: String, Codable {
    case pending
    case syncing
    case synced
    case failed
}

