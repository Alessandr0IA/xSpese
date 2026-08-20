import SwiftData
import SwiftUI
import UIKit

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Transaction.transactionDate, order: .reverse) private var transactions: [Transaction]

    @State private var showsSettings = false
    @State private var showsManualEntry = false
    @State private var selectedTransaction: Transaction?
    @State private var isSyncing = false
    @State private var searchText = ""
    @State private var filter: TransactionFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "Nessun movimento",
                        systemImage: "creditcard",
                        description: Text("Registra una spesa da Comandi Rapidi o con il pulsante +.")
                    )
                } else {
                    List {
                        Section {
                            Picker("Filtro", selection: $filter) {
                                ForEach(TransactionFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            LabeledContent("Totale visualizzato") {
                                Text(filteredTotal, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                    .fontWeight(.semibold)
                            }
                        }

                        if filteredTransactions.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ForEach(groupedTransactions, id: \.date) { group in
                                Section {
                                    ForEach(group.transactions) { transaction in
                                        transactionLink(transaction)
                                    }
                                } header: {
                                    Text(group.date, format: .dateTime.weekday(.wide).day().month().year())
                                } footer: {
                                    HStack {
                                        Text("Totale giorno")
                                        Spacer()
                                        Text(group.total, format: .currency(code: UserDefaults.standard.defaultCurrency))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Movimenti")
            .searchable(text: $searchText, prompt: "Esercente, categoria o carta")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: synchronizeNow) {
                        if isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .disabled(isSyncing)
                    .accessibilityLabel("Sincronizza ora")

                    Button {
                        showsManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuova spesa manuale")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Impostazioni")
                }
            }
            .refreshable { await synchronize() }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .sheet(isPresented: $showsManualEntry) { ManualTransactionView() }
            .sheet(item: $selectedTransaction) { transaction in
                NavigationStack { TransactionDetailView(transaction: transaction) }
            }
            .task {
                if UserDefaults.standard.automaticSyncEnabled { await synchronize() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, UserDefaults.standard.automaticSyncEnabled { synchronizeNow() }
            }
        }
    }

    @ViewBuilder
    private func transactionLink(_ transaction: Transaction) -> some View {
        NavigationLink {
            TransactionDetailView(transaction: transaction)
        } label: {
            TransactionRow(transaction: transaction)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if transaction.syncStatus != .synced {
                Button {
                    retry(transaction)
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button {
                selectedTransaction = transaction
            } label: {
                Label("Visualizza dettagli", systemImage: "doc.text.magnifyingglass")
            }
            if transaction.syncStatus != .synced {
                Button {
                    retry(transaction)
                } label: {
                    Label("Riprova sincronizzazione", systemImage: "arrow.clockwise")
                }
            }
            Button {
                UIPasteboard.general.string = transaction.id.uuidString
            } label: {
                Label("Copia identificativo", systemImage: "doc.on.doc")
            }
        }
    }

    private var filteredTransactions: [Transaction] {
        transactions.filter { transaction in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .toSync: transaction.syncStatus != .synced
            case .synced: transaction.syncStatus == .synced
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let haystack = [transaction.merchant, transaction.category, transaction.paymentMethod, transaction.note]
                .compactMap { $0 }
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedTransactions: [(date: Date, transactions: [Transaction], total: Decimal)] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) {
            calendar.startOfDay(for: $0.transactionDate)
        }
        return groups.map { date, transactions in
            (date, transactions, transactions.reduce(Decimal.zero) { $0 + $1.amount })
        }.sorted { $0.date > $1.date }
    }

    private var filteredTotal: Decimal {
        filteredTransactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func synchronizeNow() {
        Task { await synchronize() }
    }

    private func retry(_ transaction: Transaction) {
        Task { @MainActor in
            await SyncService.shared.sync(transaction, in: modelContext)
        }
    }

    @MainActor
    private func synchronize() async {
        guard !isSyncing else { return }
        isSyncing = true
        await SyncService.shared.syncPendingTransactions(in: modelContext)
        isSyncing = false
    }
}

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all, toSync, synced
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Tutti"
        case .toSync: "Da inviare"
        case .synced: "Inviati"
        }
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(transaction.merchant).font(.headline)
                Spacer()
                Text(transaction.amount, format: .currency(code: transaction.currency)).font(.headline)
            }
            HStack {
                Text(transaction.transactionDate, format: .dateTime.hour().minute())
                if let category = transaction.category { Text("• \(category)") }
                Spacer()
                if let paymentMethod = transaction.paymentMethod { Text(paymentMethod) }
                Image(systemName: syncIcon)
                    .foregroundStyle(syncColor)
                    .accessibilityLabel(syncLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var syncIcon: String {
        switch transaction.syncStatus {
        case .pending: "clock.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var syncColor: Color {
        switch transaction.syncStatus {
        case .pending, .syncing: .orange
        case .synced: .green
        case .failed: .red
        }
    }

    private var syncLabel: String {
        switch transaction.syncStatus {
        case .pending: "In attesa di sincronizzazione"
        case .syncing: "Sincronizzazione in corso"
        case .synced: "Sincronizzato"
        case .failed: "Sincronizzazione fallita"
        }
    }
}

