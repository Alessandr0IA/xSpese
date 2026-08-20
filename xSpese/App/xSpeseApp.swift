import SwiftData
import SwiftUI

@main
struct xSpeseApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer = PersistenceController.shared.container

    init() {
        BackgroundSyncService.register()
    }

    var body: some Scene {
        WindowGroup {
            AppTabView()
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundSyncService.schedule()
            }
        }
    }
}
