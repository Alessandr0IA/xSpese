import SwiftUI

struct LoansView: View {
    @State private var loans: [LoanDTO] = []
    @State private var selectedStatus = LoanListStatus.active
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsNewLoan = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && loans.isEmpty {
                    ProgressView("Caricamento prestiti…")
                } else if let errorMessage, loans.isEmpty {
                    ContentUnavailableView {
                        Label("Prestiti non disponibili", systemImage: "banknote.fill")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Riprova") { Task { await load() } }
                        Button("Impostazioni") { showsSettings = true }
                    }
                } else if filteredLoans.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun prestito", systemImage: "checkmark.circle")
                    } description: {
                        Text(searchText.isEmpty ? "Non ci sono prestiti in questa sezione." : "Nessun risultato per la ricerca.")
                    } actions: {
                        if selectedStatus == .active && searchText.isEmpty {
                            Button("Nuovo prestito") { showsNewLoan = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    loanList
                }
            }
            .navigationTitle("Prestiti")
            .searchable(text: $searchText, prompt: "Titolo, creditore o utente")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Stato", selection: $selectedStatus) {
                    ForEach(LoanListStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showsNewLoan = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nuovo prestito")
                    Button { Task { await load() } } label: {
                        if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Aggiorna prestiti")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Impostazioni")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showsNewLoan) {
                LoanEditorView(loan: nil) { _ in await load() }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private var loanList: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    summaryItem(value: "\(activeLoans.count)", label: "Attivi", color: .blue)
                    Divider()
                    summaryItem(value: money(totalOutstanding), label: "Residuo", color: totalOutstanding > 0 ? .orange : .green)
                    Divider()
                    summaryItem(value: money(installmentCommitment), label: "Rate", color: .primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section(selectedStatus.title) {
                ForEach(filteredLoans) { loan in
                    NavigationLink {
                        LoanDetailView(initialLoan: loan) { await load() }
                    } label: {
                        LoanRow(loan: loan)
                    }
                }
            }
        }
    }

    private var activeLoans: [LoanDTO] { loans.filter { !$0.isCompleted } }
    private var totalOutstanding: Decimal { activeLoans.reduce(0) { $0 + $1.remainingAmount } }
    private var installmentCommitment: Decimal { activeLoans.compactMap(\.installmentAmount).reduce(0, +) }

    private var filteredLoans: [LoanDTO] {
        loans
            .filter { loan in
                switch selectedStatus {
                case .active: !loan.isCompleted
                case .completed: loan.isCompleted
                case .all: true
                }
            }
            .filter { loan in
                guard !searchText.isEmpty else { return true }
                return [loan.title, loan.lender, loan.borrower, loan.user, loan.category]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                ($0.nextPaymentDateValue ?? .distantFuture) < ($1.nextPaymentDateValue ?? .distantFuture)
            }
    }

    private func summaryItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: UserDefaults.standard.defaultCurrency).precision(.fractionLength(0...2)))
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            loans = try await SyncService.shared.configuredClient().fetchLoans()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanRow: View {
    let loan: LoanDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.title).font(.headline)
                    if let counterpart = loan.lender ?? loan.borrower {
                        Text(counterpart).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(loan.remainingAmount, format: .currency(code: loan.currency))
                    .font(.subheadline.weight(.semibold))
            }

            ProgressView(value: loan.progress)
                .tint(loan.isCompleted ? .green : .blue)

            HStack {
                if let total = loan.totalInstallments {
                    Label("\(loan.paidInstallments)/\(total) rate", systemImage: "chart.bar.fill")
                }
                Spacer()
                if loan.isCompleted {
                    Label("Estinto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if let nextDate = loan.nextPaymentDateValue {
                    Label(nextDate.formatted(.dateTime.day().month(.abbreviated)), systemImage: "calendar")
                        .foregroundStyle(nextDate < Calendar.current.startOfDay(for: .now) ? .red : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct LoanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var loan: LoanDTO
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsEditor = false
    @State private var showsPayment = false
    @State private var confirmsImport = false
    @State private var confirmsDelete = false
    let onChange: () async -> Void

    init(initialLoan: LoanDTO, onChange: @escaping () async -> Void) {
        _loan = State(initialValue: initialLoan)
        self.onChange = onChange
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(loan.remainingAmount, format: .currency(code: loan.currency))
                            .font(.largeTitle.bold())
                        Spacer()
                        Text(loan.isCompleted ? "Estinto" : loan.status.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(loan.isCompleted ? Color.green.opacity(0.14) : Color.blue.opacity(0.14), in: Capsule())
                    }
                    Text("Residuo su \(loan.totalAmount.formatted(.currency(code: loan.currency)))")
                        .foregroundStyle(.secondary)
                    ProgressView(value: loan.progress).tint(loan.isCompleted ? .green : .blue)
                }
                .padding(.vertical, 6)
            }

            Section("Piano rate") {
                if let installmentAmount = loan.installmentAmount {
                    LabeledContent("Importo rata", value: installmentAmount.formatted(.currency(code: loan.currency)))
                }
                if let totalInstallments = loan.totalInstallments {
                    LabeledContent("Rate pagate", value: "\(loan.paidInstallments) di \(totalInstallments)")
                    LabeledContent("Rate rimanenti", value: "\(loan.remainingInstallments ?? 0)")
                }
                if let nextDate = loan.nextPaymentDateValue {
                    LabeledContent("Prossima rata") { Text(nextDate, format: .dateTime.day().month().year()) }
                }
                if let dueDay = loan.dueDay { LabeledContent("Giorno pagamento", value: "\(dueDay)") }
                if let frequency = loan.frequency { LabeledContent("Frequenza", value: frequency.capitalized) }
                if let interestRate = loan.interestRate {
                    LabeledContent("Tasso", value: "\(NSDecimalNumber(decimal: interestRate).stringValue)%")
                }
            }

            Section("Informazioni") {
                if let type = loan.type { LabeledContent("Tipo", value: type.capitalized) }
                if let lender = loan.lender { LabeledContent("Creditore", value: lender) }
                if let borrower = loan.borrower { LabeledContent("Debitore", value: borrower) }
                if let user = loan.user { LabeledContent("Utente", value: user) }
                if let category = loan.category { LabeledContent("Categoria", value: category) }
                if let startDate = loan.startDateValue {
                    LabeledContent("Data iniziale") { Text(startDate, format: .dateTime.day().month().year()) }
                }
                if let paymentMethod = loan.paymentMethod { LabeledContent("Pagamento", value: paymentMethod) }
                if let card = loan.card { LabeledContent("Carta", value: card) }
                if let notes = loan.notes, !notes.isEmpty { Text(notes).foregroundStyle(.secondary) }
            }

            if !loan.isCompleted {
                Section("Azioni") {
                    Button { showsPayment = true } label: {
                        Label("Registra rata pagata", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(isWorking)

                    Button { confirmsImport = true } label: {
                        Label("Importa rate passate", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(isWorking)
                }
            }

            Section {
                Button(role: .destructive) { confirmsDelete = true } label: {
                    Label("Elimina prestito", systemImage: "trash")
                }
                .disabled(isWorking)
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle(loan.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifica") { showsEditor = true }.disabled(isWorking)
            }
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .task { await reload() }
        .sheet(isPresented: $showsEditor) {
            LoanEditorView(loan: loan) { updated in
                loan = updated
                await onChange()
            }
        }
        .sheet(isPresented: $showsPayment) {
            LoanPaymentView(loan: loan) { updated in
                loan = updated
                await onChange()
            }
        }
        .confirmationDialog("Importare le rate passate?", isPresented: $confirmsImport, titleVisibility: .visible) {
            Button("Importa") { Task { await importPastInstallments() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il server creerà i movimenti mancanti per le rate già trascorse, evitando i duplicati.")
        }
        .confirmationDialog("Eliminare il prestito?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Elimina definitivamente", role: .destructive) { Task { await deleteLoan() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I movimenti già creati non verranno eliminati automaticamente.")
        }
    }

    @MainActor
    private func reload() async {
        do {
            loan = try await SyncService.shared.configuredClient().fetchLoan(id: loan.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importPastInstallments() async {
        isWorking = true
        defer { isWorking = false }
        do {
            loan = try await SyncService.shared.configuredClient().importPastLoanInstallments(id: loan.id)
            errorMessage = nil
            await onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteLoan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SyncService.shared.configuredClient().deleteLoan(id: loan.id)
            await onChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let loan: LoanDTO?
    let onSave: (LoanDTO) async -> Void

    @State private var title: String
    @State private var lender: String
    @State private var borrower: String
    @State private var type: String
    @State private var totalAmount: String
    @State private var installmentAmount: String
    @State private var currency: String
    @State private var totalInstallments: Int
    @State private var paidInstallments: Int
    @State private var startDate: Date
    @State private var dueDay: Int
    @State private var frequency: String
    @State private var interestRate: String
    @State private var userID: Int
    @State private var categoryID: String
    @State private var paymentMethod: String
    @State private var card: String
    @State private var status: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(loan: LoanDTO?, onSave: @escaping (LoanDTO) async -> Void) {
        self.loan = loan
        self.onSave = onSave
        _title = State(initialValue: loan?.title ?? "")
        _lender = State(initialValue: loan?.lender ?? "")
        _borrower = State(initialValue: loan?.borrower ?? "")
        _type = State(initialValue: loan?.type ?? "ricevuto")
        _totalAmount = State(initialValue: loan.map { NSDecimalNumber(decimal: $0.totalAmount).stringValue } ?? "")
        _installmentAmount = State(initialValue: loan?.installmentAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _currency = State(initialValue: loan?.currency ?? UserDefaults.standard.defaultCurrency)
        _totalInstallments = State(initialValue: max(loan?.totalInstallments ?? 12, 1))
        _paidInstallments = State(initialValue: loan?.paidInstallments ?? 0)
        _startDate = State(initialValue: loan?.startDateValue ?? .now)
        _dueDay = State(initialValue: loan?.dueDay ?? Calendar.current.component(.day, from: .now))
        _frequency = State(initialValue: loan?.frequency ?? "mensile")
        _interestRate = State(initialValue: loan?.interestRate.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _userID = State(initialValue: loan?.userID ?? max(UserDefaults.standard.integer(forKey: "serverUserID"), 1))
        _categoryID = State(initialValue: loan?.categoryID.map(String.init) ?? "")
        _paymentMethod = State(initialValue: loan?.paymentMethod ?? "")
        _card = State(initialValue: loan?.card ?? "")
        _status = State(initialValue: loan?.status ?? "attivo")
        _notes = State(initialValue: loan?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prestito") {
                    TextField("Titolo", text: $title)
                    Picker("Tipo", selection: $type) {
                        Text("Prestito ricevuto").tag("ricevuto")
                        Text("Credito concesso").tag("concesso")
                        Text("Finanziamento").tag("finanziamento")
                    }
                    TextField("Creditore o istituto", text: $lender)
                    TextField("Debitore o beneficiario", text: $borrower)
                    Picker("Stato", selection: $status) {
                        Text("Attivo").tag("attivo")
                        Text("Sospeso").tag("sospeso")
                        Text("Estinto").tag("estinto")
                    }
                }

                Section("Importi") {
                    TextField("Importo totale", text: $totalAmount).keyboardType(.decimalPad)
                    TextField("Importo rata", text: $installmentAmount).keyboardType(.decimalPad)
                    TextField("Valuta", text: $currency).textInputAutocapitalization(.characters)
                    TextField("Tasso di interesse %", text: $interestRate).keyboardType(.decimalPad)
                }

                Section("Piano rate") {
                    Stepper("Numero rate: \(totalInstallments)", value: $totalInstallments, in: 1...600)
                    Stepper("Rate già pagate: \(paidInstallments)", value: $paidInstallments, in: 0...max(totalInstallments, 0))
                    DatePicker("Data iniziale", selection: $startDate, displayedComponents: .date)
                    Stepper("Giorno pagamento: \(dueDay)", value: $dueDay, in: 1...31)
                    Picker("Frequenza", selection: $frequency) {
                        Text("Mensile").tag("mensile")
                        Text("Settimanale").tag("settimanale")
                        Text("Trimestrale").tag("trimestrale")
                        Text("Annuale").tag("annuale")
                    }
                }

                Section("Registrazione movimenti") {
                    Stepper("ID utente: \(userID)", value: $userID, in: 1...9999)
                    TextField("ID categoria (opzionale)", text: $categoryID).keyboardType(.numberPad)
                    TextField("Metodo di pagamento", text: $paymentMethod)
                    TextField("Carta o conto", text: $card)
                }

                Section("Note") {
                    TextEditor(text: $notes).frame(minHeight: 90)
                }

                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle(loan == nil ? "Nuovo prestito" : "Modifica prestito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await save() } }.disabled(isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
    }

    @MainActor
    private func save() async {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            errorMessage = "Inserisci un titolo."
            return
        }
        guard let total = parsedDecimal(totalAmount), total > 0 else {
            errorMessage = "Inserisci un importo totale valido."
            return
        }
        let computedInstallment = parsedDecimal(installmentAmount) ?? total / Decimal(totalInstallments)
        guard computedInstallment > 0 else {
            errorMessage = "Inserisci un importo rata valido."
            return
        }

        let mutation = LoanMutation(
            title: normalizedTitle,
            lender: normalizedOrNil(lender),
            borrower: normalizedOrNil(borrower),
            type: type,
            totalAmount: total,
            installmentAmount: computedInstallment,
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            totalInstallments: totalInstallments,
            paidInstallments: min(paidInstallments, totalInstallments),
            startDate: DeadlineDTO.dateOnlyFormatter.string(from: startDate),
            dueDay: dueDay,
            frequency: frequency,
            interestRate: parsedDecimal(interestRate),
            userID: userID,
            categoryID: Int(categoryID.trimmingCharacters(in: .whitespacesAndNewlines)),
            paymentMethod: normalizedOrNil(paymentMethod),
            card: normalizedOrNil(card),
            status: status,
            notes: normalizedOrNil(notes)
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let client = try SyncService.shared.configuredClient()
            let saved = if let loan {
                try await client.updateLoan(id: loan.id, mutation: mutation)
            } else {
                try await client.createLoan(mutation)
            }
            await onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedDecimal(_ rawValue: String) -> Decimal? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func normalizedOrNil(_ rawValue: String) -> String? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private struct LoanPaymentView: View {
    @Environment(\.dismiss) private var dismiss
    let loan: LoanDTO
    let onSave: (LoanDTO) async -> Void
    @State private var paymentDate = Date.now
    @State private var createsMovement = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Rata") {
                    LabeledContent("Prestito", value: loan.title)
                    if let amount = loan.installmentAmount {
                        LabeledContent("Importo", value: amount.formatted(.currency(code: loan.currency)))
                    }
                    DatePicker("Data pagamento", selection: $paymentDate, displayedComponents: .date)
                    Toggle("Crea movimento di spesa", isOn: $createsMovement)
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Registra rata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma") { Task { await pay() } }.disabled(isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
    }

    @MainActor
    private func pay() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let request = LoanPaymentRequest(
                paymentDate: DeadlineDTO.dateOnlyFormatter.string(from: paymentDate),
                createsMovement: createsMovement
            )
            let updated = try await SyncService.shared.configuredClient().payLoanInstallment(id: loan.id, request: request)
            await onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
