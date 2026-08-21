import SwiftUI
import SwiftData

struct AppTabView: View {
    @Query private var transactions: [Transaction]
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionsView()
                .tabItem {
                    Label("Movimenti", systemImage: "list.bullet.rectangle")
                }
                .badge(unsyncedCount)
                .tag(0)

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag(1)

            ServerMovementsView()
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }
                .tag(2)

            DeadlinesView()
                .tabItem {
                    Label("Scadenze", systemImage: "calendar.badge.clock")
                }
                .tag(3)

            LoansView()
                .tabItem {
                    Label("Prestiti", systemImage: "banknote.fill")
                }
                .tag(4)
        }
        .onOpenURL { url in
            guard url.scheme == "xspese" else { return }
            switch url.host {
            case "movimenti": selectedTab = 0
            case "dashboard": selectedTab = 1
            case "server": selectedTab = 2
            case "scadenze": selectedTab = 3
            case "prestiti": selectedTab = 4
            default: break
            }
        }
        .task {
            async let deadlines: Void = DeadlineWidgetCacheService.refresh()
            async let expenses: Void = ExpenseWidgetCacheService.refreshAll()
            _ = await (deadlines, expenses)
        }
    }

    private var unsyncedCount: Int {
        transactions.filter { $0.syncStatus != .synced }.count
    }
}
