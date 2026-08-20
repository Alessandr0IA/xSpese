import SwiftData
import SwiftUI

struct ManualTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.createdAt, order: .reverse) private var previousTransactions: [Transaction]
    @AppStorage("serverUserID") private var defaultUserID = 1
    @AppStorage("defaultCurrency") private var defaultCurrency = "EUR"

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var transactionDate = Date.now
    @State private var paymentMethod = ""
    @State private var selectedCategoryID: Int?
    @State private var note = ""
    @State private var userID = 1
    @State private var categories: [ExpenseCategory] = []
    @State private var merchantRules: [MerchantRuleDTO] = []
    @State private var isLoadingCategories = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Spesa") {
                    TextField("Importo", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Esercente", text: $merchant)
                        .textInputAutocapitalization(.words)
                    DatePicker("Data e ora", selection: $transactionDate)
                }

                Section("Dettagli") {
                    TextField("Carta o conto", text: $paymentMethod)
                    if !suggestedPaymentMethods.isEmpty {
                        Picker("Carte recenti", selection: $paymentMethod) {
                            Text("Nessuna selezione").tag("")
                            ForEach(suggestedPaymentMethods, id: \.self) { method in
                                Text(method).tag(method)
                            }
                        }
                    }

                    Picker("Categoria", selection: $selectedCategoryID) {
                        Text("Automatica dal server").tag(nil as Int?)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    if selectedCategoryID == nil, let suggestedRule {
                        Button {
                            selectedCategoryID = suggestedRule.categoryID
                        } label: {
                            Label(
                                "Suggerita: \(suggestedRule.category ?? "Categoria #\(suggestedRule.categoryID)")",
                                systemImage: "wand.and.stars"
                            )
                        }
                    }

                    TextField("Valuta", text: $defaultCurrency)
                        .textInputAutocapitalization(.characters)
                    Stepper("ID utente: \(userID)", value: $userID, in: 1...9999)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isLoadingCategories {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Caricamento categorie…")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nuova spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(amountText.isEmpty || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                userID = max(defaultUserID, 1)
                await loadCategories()
            }
        }
    }

    private var suggestedPaymentMethods: [String] {
        var seen = Set<String>()
        return previousTransactions.compactMap(\.paymentMethod).filter { seen.insert($0).inserted }.prefix(5).map { $0 }
    }

    private func save() {
        let normalizedAmount = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: normalizedAmount, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            errorMessage = "Inserisci un importo valido maggiore di zero."
            return
        }

        let category = categories.first { $0.id == selectedCategoryID }
        let transaction = Transaction(
            amount: amount,
            currency: normalizedCurrency,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            transactionDate: transactionDate,
            paymentMethod: paymentMethod.nilIfBlank,
            category: category?.name,
            categoryID: category?.id,
            note: note.nilIfBlank,
            userID: userID,
            source: .manual
        )
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            ExpenseWidgetCacheService.updateSyncStatus()
            dismiss()
            if UserDefaults.standard.automaticSyncEnabled {
                Task { @MainActor in
                    await SyncService.shared.sync(transaction, in: modelContext)
                }
            }
        } catch {
            errorMessage = "Salvataggio locale fallito: \(error.localizedDescription)"
        }
    }

    private var normalizedCurrency: String {
        let value = defaultCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.count == 3 ? value : "EUR"
    }

    private var suggestedRule: MerchantRuleDTO? {
        let normalizedMerchant = merchant.lowercased()
        guard !normalizedMerchant.isEmpty else { return nil }
        return merchantRules.first {
            $0.active != 0 && normalizedMerchant.contains($0.keyword.lowercased())
        }
    }

    @MainActor
    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let client = try SyncService.shared.configuredClient()
            async let loadedCategories = client.fetchCategories()
            async let loadedRules = client.fetchMerchantRules()
            categories = try await loadedCategories
            merchantRules = try await loadedRules
        } catch {
            errorMessage = "Categorie non disponibili: \(error.localizedDescription)"
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
