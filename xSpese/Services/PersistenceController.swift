import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)

        do {
            container = try ModelContainer(
                for: Transaction.self,
                configurations: configuration
            )
        } catch {
            fatalError("Impossibile creare il database locale: \(error.localizedDescription)")
        }
    }
}

