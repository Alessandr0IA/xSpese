import SwiftUI

struct MerchantRulesView: View {
    @State private var rules: [MerchantRuleDTO] = []
    @State private var categories: [ExpenseCategory] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsNewRule = false

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.keyword)
                        .font(.headline)
                    Text(rule.category ?? "Categoria #\(rule.categoryID)")
                        .foregroundStyle(.secondary)
                    if rule.deductible730 == 1 {
                        Label(rule.deductibleType ?? "Detraibile 730", systemImage: "cross.case.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .overlay {
            if isLoading && rules.isEmpty { ProgressView() }
        }
        .navigationTitle("Regole esercenti")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewRule = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(categories.isEmpty)
                .accessibilityLabel("Nuova regola")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showsNewRule) {
            NewMerchantRuleView(categories: categories) {
                await load()
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = try SyncService.shared.configuredClient()
            async let loadedRules = client.fetchMerchantRules()
            async let loadedCategories = client.fetchCategories()
            rules = try await loadedRules
            categories = try await loadedCategories
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewMerchantRuleView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [ExpenseCategory]
    let onSaved: () async -> Void

    @State private var keyword = ""
    @State private var categoryID: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Parola chiave esercente", text: $keyword)
                    .textInputAutocapitalization(.never)
                Picker("Categoria", selection: $categoryID) {
                    Text("Seleziona").tag(nil as Int?)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nuova regola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await save() } }
                        .disabled(keyword.nilIfBlank == nil || categoryID == nil || isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let keyword = keyword.nilIfBlank, let categoryID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SyncService.shared.configuredClient().createMerchantRule(keyword: keyword, categoryID: categoryID)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

