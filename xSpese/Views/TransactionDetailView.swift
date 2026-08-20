import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)

                    Text(transaction.amount, format: .currency(code: transaction.currency))
                        .font(.largeTitle.bold())

                    Text(transaction.merchant)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section("Movimento") {
                LabeledContent("Data") {
                    Text(transaction.transactionDate, format: .dateTime.day().month().year())
                }
                LabeledContent("Ora") {
                    Text(transaction.transactionDate, format: .dateTime.hour().minute())
                }
                LabeledContent("Valuta", value: transaction.currency)
                if let paymentMethod = transaction.paymentMethod {
                    LabeledContent("Carta o conto", value: paymentMethod)
                }
                if let category = transaction.category {
                    LabeledContent("Categoria", value: category)
                }
                if let userID = transaction.userID {
                    LabeledContent("ID utente", value: String(userID))
                }
                if let note = transaction.note {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note)
                    }
                }
                LabeledContent("Origine", value: sourceLabel)
            }

            Section("Sincronizzazione") {
                LabeledContent("Stato") {
                    Label(syncLabel, systemImage: syncIcon)
                        .foregroundStyle(syncColor)
                }
                LabeledContent("Tentativi", value: String(transaction.syncAttemptCount))
                LabeledContent("Creato") {
                    Text(transaction.createdAt, format: .dateTime.day().month().year().hour().minute())
                }
                LabeledContent("Aggiornato") {
                    Text(transaction.updatedAt, format: .dateTime.day().month().year().hour().minute())
                }
                if let lastSyncAttempt = transaction.lastSyncAttempt {
                    LabeledContent("Ultimo tentativo") {
                        Text(lastSyncAttempt, format: .dateTime.day().month().year().hour().minute())
                    }
                }
                if let syncError = transaction.syncError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Errore")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(syncError)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Identificativo locale") {
                Text(transaction.id.uuidString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Dettaglio spesa")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceLabel: String {
        switch transaction.source {
        case .shortcut: "Comandi Rapidi"
        case .manual: "Inserimento manuale"
        case .imported: "Importato"
        }
    }

    private var syncLabel: String {
        switch transaction.syncStatus {
        case .pending: "Da sincronizzare"
        case .syncing: "Sincronizzazione…"
        case .synced: "Sincronizzato"
        case .failed: "Errore"
        }
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
}
