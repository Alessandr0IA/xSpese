import AppIntents
import Foundation
import OSLog
import SwiftData

struct RegistraSpesaIntent: AppIntent {
    static let title: LocalizedStringResource = "Registra spesa"
    static let description = IntentDescription("Salva una spesa nel database locale di xSpese.")
    static let openAppWhenRun = false

    @Parameter(title: "Importo", requestValueDialog: "Qual è l'importo della spesa?")
    var amount: Double

    @Parameter(title: "Esercente", requestValueDialog: "Qual è il nome dell'esercente?")
    var merchant: String

    @Parameter(title: "Data e ora")
    var transactionDate: Date

    @Parameter(title: "Carta o conto")
    var paymentMethod: String?

    @Parameter(title: "Categoria")
    var category: String?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Valuta")
    var currency: String?

    @Parameter(title: "ID utente")
    var userID: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Registra una spesa presso \(\.$merchant)") {
            \.$amount
            \.$transactionDate
            \.$paymentMethod
            \.$category
            \.$note
            \.$currency
            \.$userID
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        guard amount > 0, amount.isFinite else {
            throw RegistraSpesaError.invalidAmount
        }
        guard !normalizedMerchant.isEmpty else {
            throw RegistraSpesaError.missingMerchant
        }

        let transaction = Transaction(
            amount: Decimal(amount),
            currency: currency?.nilIfBlank?.uppercased() ?? UserDefaults.standard.defaultCurrency,
            merchant: normalizedMerchant,
            transactionDate: transactionDate,
            paymentMethod: paymentMethod?.nilIfBlank,
            category: category?.nilIfBlank,
            note: note?.nilIfBlank,
            userID: userID
        )
        let context = PersistenceController.shared.container.mainContext
        context.insert(transaction)

        do {
            try context.save()
            Logger.intent.info("Transazione salvata localmente: \(transaction.id, privacy: .public)")
        } catch {
            Logger.intent.error("Salvataggio locale fallito: \(error.localizedDescription, privacy: .public)")
            throw RegistraSpesaError.persistenceFailed
        }

        ExpenseWidgetCacheService.updateSyncStatus()
        if UserDefaults.standard.automaticSyncEnabled {
            await SyncService.shared.sync(transaction, in: context)
        }

        let message = transaction.syncStatus == .synced
            ? "Spesa registrata e sincronizzata."
            : "Spesa salvata sul dispositivo. La sincronizzazione verrà riprovata."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

enum RegistraSpesaError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case missingMerchant
    case persistenceFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "Inserisci un importo maggiore di zero."
        case .missingMerchant: "Inserisci il nome dell'esercente."
        case .persistenceFailed: "Non è stato possibile salvare la spesa sul dispositivo."
        }
    }
}

struct xSpeseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegistraSpesaIntent(),
            phrases: [
                "Registra una spesa con \(.applicationName)",
                "Aggiungi una spesa a \(.applicationName)"
            ],
            shortTitle: "Registra spesa",
            systemImageName: "eurosign.circle"
        )
    }
}

private extension Logger {
    static let intent = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xSpese", category: "AppIntent")
}
