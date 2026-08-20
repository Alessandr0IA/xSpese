import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serverBaseURL") private var serverBaseURL = "http://100.112.193.68:3030"
    @AppStorage("serverUserID") private var serverUserID = 1
    @AppStorage("deviceName") private var deviceName = ""
    @AppStorage("automaticSyncEnabled") private var automaticSyncEnabled = true
    @AppStorage("defaultCurrency") private var defaultCurrency = "EUR"
    @AppStorage("syncFailureNotificationsEnabled") private var syncFailureNotificationsEnabled = false
    @AppStorage("deadlineNotificationsEnabled") private var deadlineNotificationsEnabled = false
    @AppStorage("lastSuccessfulSyncTimestamp") private var lastSuccessfulSyncTimestamp = 0.0

    @State private var apiToken = ""
    @State private var isTesting = false
    @State private var isRefreshingWidgets = false
    @State private var message: StatusMessage?
    @State private var widgetMessage: StatusMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Raspberry Pi") {
                    TextField("https://spese.example.it/api/v1", text: $serverBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    SecureField("API token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Stepper("ID utente: \(serverUserID)", value: $serverUserID, in: 1...9999)

                    TextField("Nome dispositivo", text: $deviceName)
                    TextField("Valuta predefinita", text: $defaultCurrency)
                        .textInputAutocapitalization(.characters)
                    Toggle("Sincronizzazione automatica", isOn: $automaticSyncEnabled)
                    Toggle("Notifica errori ripetuti", isOn: $syncFailureNotificationsEnabled)
                        .onChange(of: syncFailureNotificationsEnabled) { _, enabled in
                            guard enabled else { return }
                            Task {
                                let authorized = await NotificationService.requestAuthorization()
                                if !authorized { syncFailureNotificationsEnabled = false }
                            }
                        }
                    Toggle("Promemoria scadenze", isOn: $deadlineNotificationsEnabled)
                        .onChange(of: deadlineNotificationsEnabled) { _, enabled in
                            Task {
                                if enabled {
                                    let authorized = await NotificationService.requestAuthorization()
                                    if !authorized { deadlineNotificationsEnabled = false }
                                } else {
                                    await NotificationService.removeDeadlineReminders()
                                }
                            }
                        }
                }

                Section("Automazioni") {
                    NavigationLink {
                        MerchantRulesView()
                    } label: {
                        Label("Regole esercenti", systemImage: "wand.and.stars")
                    }
                }

                Section {
                    LabeledContent("Condivisione dati") {
                        Label(
                            WidgetSharedStore.isAvailable ? "Attiva" : "Non disponibile",
                            systemImage: WidgetSharedStore.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(WidgetSharedStore.isAvailable ? .green : .red)
                    }

                    if let widgetLastUpdatedAt {
                        LabeledContent("Ultimo aggiornamento") {
                            Text(widgetLastUpdatedAt, format: .dateTime.day().month().hour().minute())
                        }
                    }

                    Button {
                        Task { await refreshWidgets() }
                    } label: {
                        HStack {
                            Text("Aggiorna widget ora")
                            Spacer()
                            if isRefreshingWidgets {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshingWidgets || !WidgetSharedStore.isAvailable)

                    if let widgetMessage {
                        Label(
                            widgetMessage.text,
                            systemImage: widgetMessage.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(widgetMessage.isSuccess ? .green : .red)
                    }
                } header: {
                    Text("Widget")
                } footer: {
                    Text("App e widget devono condividere lo stesso App Group. Dopo un aggiornamento tramite SideStore può essere necessario rimuovere e aggiungere nuovamente il widget.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test connessione")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let message {
                        Label(message.text, systemImage: message.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(message.isSuccess ? .green : .red)
                    }

                    if lastSuccessfulSyncTimestamp > 0 {
                        LabeledContent("Ultima sincronizzazione") {
                            Text(
                                Date(timeIntervalSince1970: lastSuccessfulSyncTimestamp),
                                format: .dateTime.day().month().year().hour().minute()
                            )
                        }
                    }
                } footer: {
                    Text("Il test chiama GET /health. Il token è conservato nel Keychain e inviato come x-api-token.")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveAndDismiss() }
                }
            }
            .onAppear {
                apiToken = KeychainService.loadAPIToken()
                if deviceName.isEmpty {
                    deviceName = UIDevice.current.name
                }
            }
        }
    }

    private func saveAndDismiss() {
        serverBaseURL = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = defaultCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        defaultCurrency = normalizedCurrency.count == 3 ? normalizedCurrency : "EUR"

        do {
            try KeychainService.saveAPIToken(apiToken)
            dismiss()
        } catch {
            message = StatusMessage(text: error.localizedDescription, isSuccess: false)
        }
    }

    private var widgetLastUpdatedAt: Date? {
        [
            DeadlineWidgetStore.load()?.updatedAt,
            MonthlyWidgetStore.load()?.updatedAt,
            SyncWidgetStore.load()?.updatedAt
        ]
        .compactMap { $0 }
        .max()
    }

    @MainActor
    private func refreshWidgets() async {
        guard WidgetSharedStore.isAvailable else {
            widgetMessage = StatusMessage(text: "App Group non disponibile in questa installazione.", isSuccess: false)
            return
        }

        isRefreshingWidgets = true
        defer { isRefreshingWidgets = false }

        do {
            try KeychainService.saveAPIToken(apiToken)
            let client = try SyncService.shared.configuredClient()
            let deadlines = try await client.fetchDeadlines(status: .open)
            let components = Calendar.current.dateComponents([.year, .month], from: .now)
            let report = try await client.fetchMonthlyReport(
                year: components.year ?? 0,
                month: components.month ?? 0
            )
            DeadlineWidgetCacheService.store(deadlines)
            ExpenseWidgetCacheService.store(report)
            ExpenseWidgetCacheService.updateSyncStatus()
            widgetMessage = StatusMessage(text: "Widget aggiornati con i dati del server.", isSuccess: true)
        } catch {
            widgetMessage = StatusMessage(text: "Aggiornamento fallito: \(error.localizedDescription)", isSuccess: false)
        }
    }

    @MainActor
    private func testConnection() async {
        guard let baseURL = URL(string: serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else {
            message = StatusMessage(text: "Inserisci un URL HTTP o HTTPS valido.", isSuccess: false)
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            try KeychainService.saveAPIToken(apiToken)
            let client = APIClient(baseURL: baseURL, token: apiToken, userID: serverUserID)
            try await client.healthCheck()
            message = StatusMessage(text: "Raspberry raggiungibile.", isSuccess: true)
        } catch {
            message = StatusMessage(text: "Connessione fallita: \(error.localizedDescription)", isSuccess: false)
        }
    }
}

private struct StatusMessage {
    let text: String
    let isSuccess: Bool
}
