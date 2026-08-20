import Charts
import SwiftUI

struct DashboardView: View {
    @State private var selectedMonth = Date.now
    @State private var report: MonthlyReport?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(selectedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Spacer()
                        Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month))
                    }
                }

                if isLoading && report == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Report non disponibile", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Riprova") { Task { await load() } }
                    }
                } else if let report {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Totale del mese")
                                .foregroundStyle(.secondary)
                            Text(report.total.value, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                .font(.largeTitle.bold())
                        }
                        .padding(.vertical, 8)
                    }

                    if !report.categories.isEmpty {
                        Section("Categorie") {
                            Chart(report.categories.prefix(8)) { item in
                                BarMark(
                                    x: .value("Totale", NSDecimalNumber(decimal: item.total.value).doubleValue),
                                    y: .value("Categoria", item.category)
                                )
                                .foregroundStyle(.teal.gradient)
                            }
                            .frame(height: max(180, CGFloat(min(report.categories.count, 8) * 34)))

                            ForEach(report.categories) { item in
                                LabeledContent(item.category) {
                                    Text(item.total.value, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                }
                            }
                        }
                    }

                    if !report.users.isEmpty {
                        Section("Utenti") {
                            ForEach(report.users) { item in
                                LabeledContent(item.user) {
                                    Text(item.total.value, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                }
                            }
                        }
                    }

                    if !report.deductibles.isEmpty {
                        Section("Detraibili 730") {
                            ForEach(report.deductibles) { item in
                                LabeledContent(item.type) {
                                    Text(item.total.value, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .refreshable { await load() }
            .task(id: selectedMonth) { await load() }
        }
    }

    private func changeMonth(by value: Int) {
        if let date = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = date
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let components = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
        do {
            let loadedReport = try await SyncService.shared.configuredClient().fetchMonthlyReport(
                year: components.year ?? 0,
                month: components.month ?? 0
            )
            report = loadedReport
            ExpenseWidgetCacheService.store(loadedReport)
            errorMessage = nil
        } catch {
            report = nil
            errorMessage = error.localizedDescription
        }
    }
}
