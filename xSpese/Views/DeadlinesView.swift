import SwiftUI

struct DeadlinesView: View {
    @AppStorage("deadlineNotificationsEnabled") private var deadlineNotificationsEnabled = false
    @State private var deadlines: [DeadlineDTO] = []
    @State private var selectedStatus = DeadlineListStatus.open
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsNewDeadline = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && deadlines.isEmpty {
                    ProgressView("Caricamento scadenze…")
                } else if let errorMessage, deadlines.isEmpty {
                    ContentUnavailableView {
                        Label("Scadenze non disponibili", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Riprova") { Task { await load() } }
                    }
                } else if filteredDeadlines.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna scadenza", systemImage: "calendar.badge.checkmark")
                    } description: {
                        Text(searchText.isEmpty ? "Non ci sono scadenze in questa sezione." : "Nessun risultato per la ricerca.")
                    } actions: {
                        if selectedStatus == .open && searchText.isEmpty {
                            Button("Nuova scadenza") { showsNewDeadline = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    deadlineList
                }
            }
            .navigationTitle("Scadenze")
            .searchable(text: $searchText, prompt: "Titolo, categoria o note")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Stato", selection: $selectedStatus) {
                    ForEach(DeadlineListStatus.allCases) { status in
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
                    Button {
                        Task { await load() }
                    } label: {
                        if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Aggiorna scadenze")

                    Button {
                        showsNewDeadline = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuova scadenza")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Impostazioni")
                }
            }
            .refreshable { await load() }
            .task(id: selectedStatus) { await load() }
            .sheet(isPresented: $showsNewDeadline) {
                DeadlineEditorView(deadline: nil) { _ in await refreshAfterChange() }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private var deadlineList: some View {
        List {
            if selectedStatus == .open {
                Section {
                    HStack(spacing: 18) {
                        summaryItem(value: "\(filteredDeadlines.count)", label: "Aperte", color: .blue)
                        Divider()
                        summaryItem(value: "\(overdueCount)", label: "Scadute", color: overdueCount > 0 ? .red : .secondary)
                        if let total = openTotal {
                            Divider()
                            summaryItem(
                                value: total.formatted(.currency(code: UserDefaults.standard.defaultCurrency)),
                                label: "Totale",
                                color: .primary
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }

            ForEach(DeadlineGroup.allCases) { group in
                let items = filteredDeadlines.filter { deadlineGroup(for: $0) == group }
                if !items.isEmpty {
                    Section(group.title) {
                        ForEach(items) { deadline in
                            NavigationLink {
                                DeadlineDetailView(initialDeadline: deadline) {
                                    await refreshAfterChange()
                                }
                            } label: {
                                DeadlineRow(deadline: deadline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func summaryItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredDeadlines: [DeadlineDTO] {
        guard !searchText.isEmpty else { return deadlines }
        return deadlines.filter {
            [$0.title, $0.description, $0.category, $0.user, $0.notes]
                .compactMap { $0 }
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var overdueCount: Int { filteredDeadlines.filter(\.isOverdue).count }

    private var openTotal: Decimal? {
        let amounts = filteredDeadlines.compactMap { $0.amount?.value }
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(Decimal.zero, +)
    }

    private func deadlineGroup(for deadline: DeadlineDTO) -> DeadlineGroup {
        if deadline.status == "completata" { return .completed }
        if deadline.status == "annullata" { return .cancelled }
        guard let dueDate = deadline.dueDateValue else { return .later }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let deadlineDay = calendar.startOfDay(for: dueDate)
        if deadlineDay < today { return .overdue }
        if deadlineDay == today { return .today }
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: today), deadlineDay <= nextWeek {
            return .nextSevenDays
        }
        return .later
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            deadlines = try await SyncService.shared.configuredClient().fetchDeadlines(status: selectedStatus)
                .sorted { ($0.dueDateValue ?? .distantFuture) < ($1.dueDateValue ?? .distantFuture) }
            errorMessage = nil
            if selectedStatus == .open {
                DeadlineWidgetCacheService.store(deadlines)
            }
            if deadlineNotificationsEnabled {
                await NotificationService.scheduleDeadlineReminders(for: deadlines)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshAfterChange() async {
        await load()
        if selectedStatus != .open {
            await DeadlineWidgetCacheService.refresh()
        }
    }
}

private enum DeadlineGroup: Int, CaseIterable, Identifiable {
    case overdue, today, nextSevenDays, later, completed, cancelled

    var id: Self { self }

    var title: String {
        switch self {
        case .overdue: "Scadute"
        case .today: "Oggi"
        case .nextSevenDays: "Prossimi 7 giorni"
        case .later: "Successive"
        case .completed: "Completate"
        case .cancelled: "Annullate"
        }
    }
}

private struct DeadlineRow: View {
    let deadline: DeadlineDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(deadline.title)
                        .font(.headline)
                        .lineLimit(1)
                    if deadline.priority == "alta" {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Priorità alta")
                    }
                }

                HStack(spacing: 8) {
                    if let date = deadline.dueDateValue {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                    } else {
                        Text(deadline.dueDate)
                    }
                    if let category = deadline.category {
                        Text("•")
                        Text(category).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(deadline.isOverdue ? .red : .secondary)
            }

            Spacer()
            if let amount = deadline.amount?.value {
                Text(amount, format: .currency(code: deadline.currency ?? "EUR"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 3)
    }

    private var statusIcon: String {
        if deadline.isCompleted { return "checkmark.circle.fill" }
        if deadline.status == "annullata" { return "xmark.circle.fill" }
        if deadline.isOverdue { return "exclamationmark.circle.fill" }
        return "calendar.circle.fill"
    }

    private var statusColor: Color {
        if deadline.isCompleted { return .green }
        if deadline.status == "annullata" { return .secondary }
        if deadline.isOverdue { return .red }
        return .blue
    }
}

private struct DeadlineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deadline: DeadlineDTO
    @State private var showsEditor = false
    @State private var showsCompletion = false
    @State private var showsDeleteConfirmation = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    let onChanged: () async -> Void

    init(initialDeadline: DeadlineDTO, onChanged: @escaping () async -> Void) {
        _deadline = State(initialValue: initialDeadline)
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: deadline.isCompleted ? "checkmark.circle.fill" : "calendar.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(deadline.isCompleted ? .green : deadline.isOverdue ? .red : .blue)
                    Text(deadline.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let amount = deadline.amount?.value {
                        Text(amount, format: .currency(code: deadline.currency ?? "EUR"))
                            .font(.title3.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section("Scadenza") {
                LabeledContent("Data") {
                    if let date = deadline.dueDateValue {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .foregroundStyle(deadline.isOverdue ? .red : .primary)
                    } else {
                        Text(deadline.dueDate)
                    }
                }
                LabeledContent("Stato", value: statusTitle)
                LabeledContent("Priorità", value: deadline.priority?.capitalized ?? "Normale")
                if let user = deadline.user { LabeledContent("Utente", value: user) }
                if let category = deadline.category { LabeledContent("Categoria", value: category) }
            }

            if deadline.description != nil || deadline.notes != nil {
                Section("Dettagli") {
                    if let description = deadline.description { Text(description) }
                    if let notes = deadline.notes { LabeledContent("Note", value: notes) }
                }
            }

            if let recurrence = deadline.recurrence {
                Section("Ricorrenza") {
                    LabeledContent("Frequenza", value: recurrenceTitle(recurrence))
                    if let endDate = recurrence.endDate { LabeledContent("Fine", value: endDate) }
                }
            }

            if let reminders = deadline.reminderDays, !reminders.isEmpty {
                Section("Promemoria") {
                    ForEach(reminders.sorted(by: >), id: \.self) { days in
                        Label(reminderTitle(days), systemImage: "bell")
                    }
                }
            }

            if let movementID = deadline.movementID {
                Section("Pagamento") {
                    LabeledContent("Movimento server", value: "#\(movementID)")
                }
            }

            Section {
                if deadline.isOpen {
                    Button {
                        showsCompletion = true
                    } label: {
                        Label("Segna come completata", systemImage: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else if deadline.isCompleted {
                    Button {
                        Task { await reopen() }
                    } label: {
                        Label("Riapri scadenza", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(isWorking)
                }

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Elimina scadenza", systemImage: "trash")
                }
                .disabled(isWorking)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Dettaglio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifica") { showsEditor = true }
                    .disabled(isWorking)
            }
        }
        .sheet(isPresented: $showsEditor) {
            DeadlineEditorView(deadline: deadline) { updated in
                deadline = updated
                await onChanged()
            }
        }
        .sheet(isPresented: $showsCompletion) {
            DeadlineCompletionView(deadline: deadline) { updated in
                deadline = updated
                await onChanged()
            }
        }
        .confirmationDialog(
            "Eliminare \"\(deadline.title)\"?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Elimina definitivamente", role: .destructive) {
                Task { await deleteDeadline() }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'eventuale movimento collegato non verrà eliminato.")
        }
    }

    private var statusTitle: String {
        if deadline.isOverdue { return "Scaduta" }
        switch deadline.status {
        case "completata": return "Completata"
        case "annullata": return "Annullata"
        default: return "Aperta"
        }
    }

    private func recurrenceTitle(_ recurrence: DeadlineRecurrence) -> String {
        let type = recurrence.type.capitalized
        return recurrence.interval == 1 ? type : "\(type), ogni \(recurrence.interval)"
    }

    private func reminderTitle(_ days: Int) -> String {
        switch days {
        case 0: "Il giorno della scadenza"
        case 1: "Un giorno prima"
        default: "\(days) giorni prima"
        }
    }

    @MainActor
    private func reopen() async {
        isWorking = true
        defer { isWorking = false }
        do {
            deadline = try await SyncService.shared.configuredClient().reopenDeadline(id: deadline.id)
            errorMessage = nil
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteDeadline() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SyncService.shared.configuredClient().deleteDeadline(id: deadline.id)
            await onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DeadlineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serverUserID") private var defaultUserID = 1
    @AppStorage("defaultCurrency") private var defaultCurrency = "EUR"

    let deadline: DeadlineDTO?
    let onSaved: (DeadlineDTO) async -> Void

    @State private var title: String
    @State private var details: String
    @State private var dueDate: Date
    @State private var amountText: String
    @State private var currency: String
    @State private var userID: Int
    @State private var selectedCategoryID: Int?
    @State private var priority: String
    @State private var notes: String
    @State private var reminderDays: Set<Int>
    @State private var recurrenceType: RecurrenceChoice
    @State private var recurrenceInterval: Int
    @State private var hasRecurrenceEnd: Bool
    @State private var recurrenceEnd: Date
    @State private var categories: [ExpenseCategory] = []
    @State private var isSaving = false
    @State private var isLoadingCategories = false
    @State private var errorMessage: String?

    init(deadline: DeadlineDTO?, onSaved: @escaping (DeadlineDTO) async -> Void) {
        self.deadline = deadline
        self.onSaved = onSaved
        _title = State(initialValue: deadline?.title ?? "")
        _details = State(initialValue: deadline?.description ?? "")
        _dueDate = State(initialValue: deadline?.dueDateValue ?? .now)
        _amountText = State(initialValue: deadline?.amount.map { NSDecimalNumber(decimal: $0.value).stringValue } ?? "")
        _currency = State(initialValue: deadline?.currency ?? UserDefaults.standard.defaultCurrency)
        _userID = State(initialValue: max(deadline?.userID ?? UserDefaults.standard.integer(forKey: "serverUserID"), 1))
        _selectedCategoryID = State(initialValue: deadline?.categoryID)
        _priority = State(initialValue: deadline?.priority ?? "normale")
        _notes = State(initialValue: deadline?.notes ?? "")
        _reminderDays = State(initialValue: Set(deadline?.reminderDays ?? [7, 1, 0]))
        _recurrenceType = State(initialValue: RecurrenceChoice(rawValue: deadline?.recurrence?.type ?? "") ?? .none)
        _recurrenceInterval = State(initialValue: max(deadline?.recurrence?.interval ?? 1, 1))
        let recurrenceEndDate = deadline?.recurrence?.endDate.flatMap(DeadlineDTO.dateOnlyFormatter.date)
        _hasRecurrenceEnd = State(initialValue: recurrenceEndDate != nil)
        _recurrenceEnd = State(initialValue: recurrenceEndDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scadenza") {
                    TextField("Titolo", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Descrizione", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                    DatePicker("Data", selection: $dueDate, displayedComponents: .date)
                }

                Section("Importo") {
                    TextField("Importo facoltativo", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Valuta", text: $currency)
                        .textInputAutocapitalization(.characters)
                }

                Section("Organizzazione") {
                    Stepper("ID utente: \(userID)", value: $userID, in: 1...9999)
                    Picker("Categoria", selection: $selectedCategoryID) {
                        Text("Nessuna").tag(nil as Int?)
                        if let selectedCategoryID,
                           !categories.contains(where: { $0.id == selectedCategoryID }) {
                            Text(deadline?.category ?? "Categoria #\(selectedCategoryID)")
                                .tag(Optional(selectedCategoryID))
                        }
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    Picker("Priorità", selection: $priority) {
                        Text("Bassa").tag("bassa")
                        Text("Normale").tag("normale")
                        Text("Alta").tag("alta")
                    }
                    TextField("Note", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Promemoria") {
                    ForEach([7, 3, 1, 0], id: \.self) { days in
                        Toggle(reminderTitle(days), isOn: reminderBinding(for: days))
                    }
                }

                Section("Ricorrenza") {
                    Picker("Ripeti", selection: $recurrenceType) {
                        ForEach(RecurrenceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    if recurrenceType != .none {
                        Stepper("Ogni \(recurrenceInterval)", value: $recurrenceInterval, in: 1...99)
                        Toggle("Data di fine", isOn: $hasRecurrenceEnd)
                        if hasRecurrenceEnd {
                            DatePicker("Fine", selection: $recurrenceEnd, in: dueDate..., displayedComponents: .date)
                        }
                    }
                }

                if isLoadingCategories {
                    Section { HStack { ProgressView(); Text("Caricamento categorie…") } }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(deadline == nil ? "Nuova scadenza" : "Modifica scadenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .task { await loadCategories() }
        }
    }

    private func reminderBinding(for days: Int) -> Binding<Bool> {
        Binding(
            get: { reminderDays.contains(days) },
            set: { enabled in
                if enabled { reminderDays.insert(days) } else { reminderDays.remove(days) }
            }
        )
    }

    private func reminderTitle(_ days: Int) -> String {
        switch days {
        case 0: "Il giorno stesso"
        case 1: "Un giorno prima"
        default: "\(days) giorni prima"
        }
    }

    @MainActor
    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            categories = try await SyncService.shared.configuredClient().fetchCategories()
        } catch {
            errorMessage = "Categorie non disponibili: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func save() async {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        var amount: Decimal?
        if !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = amountText.replacingOccurrences(of: ",", with: ".")
            guard let parsed = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), parsed >= 0 else {
                errorMessage = "Inserisci un importo valido oppure lascia il campo vuoto."
                return
            }
            amount = parsed
        }

        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3 else {
            errorMessage = "La valuta deve contenere tre lettere, per esempio EUR."
            return
        }

        let recurrence: DeadlineRecurrence? = recurrenceType == .none ? nil : DeadlineRecurrence(
            type: recurrenceType.rawValue,
            interval: recurrenceInterval,
            endDate: hasRecurrenceEnd ? DeadlineDTO.dateOnlyFormatter.string(from: recurrenceEnd) : nil
        )
        let mutation = DeadlineMutation(
            uuid: deadline?.uuid ?? UUID().uuidString,
            title: normalizedTitle,
            description: details.nilIfBlank,
            dueDate: DeadlineDTO.dateOnlyFormatter.string(from: dueDate),
            amount: amount,
            currency: normalizedCurrency,
            userID: userID,
            categoryID: selectedCategoryID,
            priority: priority,
            notes: notes.nilIfBlank,
            reminderDays: reminderDays.sorted(by: >),
            recurrence: recurrence
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let client = try SyncService.shared.configuredClient()
            let saved: DeadlineDTO
            if let deadline {
                saved = try await client.updateDeadline(id: deadline.id, mutation: mutation)
            } else {
                saved = try await client.createDeadline(mutation)
            }
            await onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum RecurrenceChoice: String, CaseIterable, Identifiable {
    case none = ""
    case daily = "giornaliera"
    case weekly = "settimanale"
    case monthly = "mensile"
    case yearly = "annuale"

    var id: Self { self }
    var title: String {
        switch self {
        case .none: "Mai"
        case .daily: "Giornaliera"
        case .weekly: "Settimanale"
        case .monthly: "Mensile"
        case .yearly: "Annuale"
        }
    }
}

private struct DeadlineCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    let deadline: DeadlineDTO
    let onCompleted: (DeadlineDTO) async -> Void

    @State private var completedAt = Date.now
    @State private var createsMovement: Bool
    @State private var amountText: String
    @State private var merchant: String
    @State private var paymentMethod = "Manuale"
    @State private var card = ""
    @State private var note: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(deadline: DeadlineDTO, onCompleted: @escaping (DeadlineDTO) async -> Void) {
        self.deadline = deadline
        self.onCompleted = onCompleted
        _createsMovement = State(initialValue: deadline.amount != nil)
        _amountText = State(initialValue: deadline.amount.map { NSDecimalNumber(decimal: $0.value).stringValue } ?? "")
        _merchant = State(initialValue: deadline.title)
        _note = State(initialValue: deadline.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Completamento") {
                    DatePicker("Data e ora", selection: $completedAt)
                    Toggle("Crea anche il movimento", isOn: $createsMovement)
                }

                if createsMovement {
                    Section("Movimento") {
                        TextField("Importo", text: $amountText).keyboardType(.decimalPad)
                        TextField("Esercente", text: $merchant)
                        TextField("Metodo di pagamento", text: $paymentMethod)
                        TextField("Carta o conto", text: $card)
                        TextField("Note", text: $note, axis: .vertical).lineLimit(2...4)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Completa scadenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Completa") { Task { await complete() } }.disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    private func complete() async {
        var movement: DeadlineMovementPayload?
        if createsMovement {
            let normalized = amountText.replacingOccurrences(of: ",", with: ".")
            guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
                errorMessage = "Inserisci un importo maggiore di zero."
                return
            }
            let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedMerchant.isEmpty else {
                errorMessage = "Inserisci l'esercente del movimento."
                return
            }
            movement = DeadlineMovementPayload(
                transactionUUID: UUID().uuidString,
                paymentDate: Self.serverDateFormatter.string(from: completedAt),
                amount: amount,
                currency: deadline.currency ?? UserDefaults.standard.defaultCurrency,
                merchant: normalizedMerchant,
                paymentMethod: paymentMethod.nilIfBlank ?? "Manuale",
                card: card.nilIfBlank,
                note: note.nilIfBlank
            )
        }

        let request = DeadlineCompletionRequest(
            completedAt: ISO8601DateFormatter().string(from: completedAt),
            createsMovement: createsMovement,
            movement: movement
        )
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await SyncService.shared.configuredClient()
                .completeDeadline(id: deadline.id, request: request)
            await onCompleted(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
