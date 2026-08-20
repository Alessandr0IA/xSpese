import SwiftUI

struct ServerMovementsView: View {
    @State private var movements: [ServerMovement] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMovement: ServerMovement?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && movements.isEmpty {
                    ProgressView("Caricamento movimenti…")
                } else if let errorMessage, movements.isEmpty {
                    ContentUnavailableView {
                        Label("Server non disponibile", systemImage: "server.rack")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Riprova") { Task { await load() } }
                    }
                } else {
                    List(filteredMovements) { movement in
                        Button {
                            selectedMovement = movement
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(movement.merchant ?? "Movimento #\(movement.id)")
                                        .font(.headline)
                                    Spacer()
                                    Text(movement.amount.value, format: .currency(code: movement.currency ?? "EUR"))
                                        .font(.headline)
                                }
                                HStack {
                                    if let date = movement.paymentDateValue {
                                        Text(date, format: .dateTime.day().month().year().hour().minute())
                                    } else {
                                        Text(movement.paymentDate)
                                    }
                                    Spacer()
                                    if let category = movement.category { Text(category) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Movimenti server")
            .searchable(text: $searchText, prompt: "Esercente, categoria o utente")
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $selectedMovement) { movement in
                NavigationStack { ServerMovementDetailView(movement: movement) }
            }
        }
    }

    private var filteredMovements: [ServerMovement] {
        guard !searchText.isEmpty else { return movements }
        return movements.filter {
            [$0.merchant, $0.category, Optional($0.user), $0.card]
                .compactMap { $0 }
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            movements = try await SyncService.shared.configuredClient().fetchMovements(limit: 200)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ServerMovementDetailView: View {
    let movement: ServerMovement

    var body: some View {
        List {
            Section {
                Text(movement.amount.value, format: .currency(code: movement.currency ?? "EUR"))
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
            }
            Section("Movimento") {
                LabeledContent("Esercente", value: movement.merchant ?? "—")
                LabeledContent("Data") {
                    if let date = movement.paymentDateValue {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else {
                        Text(movement.paymentDate)
                    }
                }
                LabeledContent("Utente", value: movement.user)
                if let category = movement.category { LabeledContent("Categoria", value: category) }
                if let method = movement.paymentMethod { LabeledContent("Metodo", value: method) }
                if let card = movement.card { LabeledContent("Carta", value: card) }
                if let note = movement.note { LabeledContent("Note", value: note) }
            }
            if movement.deductible730 == 1 {
                Section("730") {
                    Label(movement.deductibleType ?? "Spesa detraibile", systemImage: "cross.case.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Movimento #\(movement.id)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
