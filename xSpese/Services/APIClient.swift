import Foundation

struct APIClient {
    private let baseURL: URL
    private let token: String
    private let defaultUserID: Int

    init(baseURL: URL, token: String, userID: Int) {
        self.baseURL = baseURL
        self.token = token
        self.defaultUserID = userID
    }

    func healthCheck() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try await execute(request, requiresAuthentication: false)
    }

    func createMovement(from transaction: Transaction) async throws -> MovementResponse {
        let payload = NewMovement(
            transactionUUID: transaction.id.uuidString,
            userID: transaction.userID ?? defaultUserID,
            paymentDate: Self.serverDateFormatter.string(from: transaction.transactionDate),
            amount: transaction.amount,
            currency: transaction.currency,
            merchant: transaction.merchant,
            appleCategory: transaction.category,
            categoryID: transaction.categoryID,
            paymentMethod: transaction.source == .manual ? "Manuale" : "Apple Pay",
            card: transaction.paymentMethod,
            note: transaction.note
        )

        let endpoint = transaction.source == .manual ? "api/movimento/manuale" : "api/movimento"
        var request = authenticatedRequest(path: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await execute(request)
        let response = try JSONDecoder().decode(MovementResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response
    }

    func fetchMovements(limit: Int = 100) async throws -> [ServerMovement] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/movimenti"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 500)))]
        guard let url = components?.url else { throw APIError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await execute(request)
        let response = try JSONDecoder().decode(MovementsResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response.movements
    }

    func fetchCategories() async throws -> [ExpenseCategory] {
        let data = try await execute(authenticatedRequest(path: "api/categorie"))
        let response = try JSONDecoder().decode(CategoriesResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response.categories.filter { $0.isActive }
    }

    func fetchMerchantRules() async throws -> [MerchantRuleDTO] {
        let data = try await execute(authenticatedRequest(path: "api/regole"))
        let response = try JSONDecoder().decode(MerchantRulesResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response.rules
    }

    func createMerchantRule(keyword: String, categoryID: Int) async throws {
        var request = authenticatedRequest(path: "api/regole", method: "POST")
        request.httpBody = try JSONEncoder().encode(NewMerchantRule(keyword: keyword, categoryID: categoryID))
        let data = try await execute(request)
        let response = try JSONDecoder().decode(SaveResponse.self, from: data)
        guard response.ok, response.saved else { throw APIError.serverRejected }
    }

    func fetchMonthlyReport(year: Int, month: Int) async throws -> MonthlyReport {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/report/mese"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "anno", value: String(year)),
            URLQueryItem(name: "mese", value: String(month))
        ]
        guard let url = components?.url else { throw APIError.invalidConfiguration }
        let data = try await execute(URLRequest(url: url))
        let response = try JSONDecoder().decode(MonthlyReport.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response
    }

    func fetchDeadlines(
        status: DeadlineListStatus = .open,
        from: Date? = nil,
        to: Date? = nil,
        query: String? = nil,
        limit: Int = 200
    ) async throws -> [DeadlineDTO] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/scadenze"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "stato", value: status.rawValue),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 500)))
        ]
        if let from {
            queryItems.append(URLQueryItem(name: "dal", value: DeadlineDTO.dateOnlyFormatter.string(from: from)))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "al", value: DeadlineDTO.dateOnlyFormatter.string(from: to)))
        }
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidConfiguration }

        let data = try await execute(URLRequest(url: url))
        let response = try JSONDecoder().decode(DeadlinesResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response.deadlines
    }

    func fetchDeadline(id: Int) async throws -> DeadlineDTO {
        let data = try await execute(authenticatedRequest(path: "api/scadenze/\(id)"))
        let response = try JSONDecoder().decode(DeadlineResponse.self, from: data)
        guard response.ok else { throw APIError.serverRejected }
        return response.deadline
    }

    func createDeadline(_ mutation: DeadlineMutation) async throws -> DeadlineDTO {
        var request = authenticatedRequest(path: "api/scadenze", method: "POST")
        request.httpBody = try JSONEncoder().encode(mutation)
        let data = try await execute(request)
        let response = try JSONDecoder().decode(DeadlineSaveResponse.self, from: data)
        guard response.ok, response.saved else { throw APIError.serverRejected }
        return response.deadline
    }

    func updateDeadline(id: Int, mutation: DeadlineMutation) async throws -> DeadlineDTO {
        var request = authenticatedRequest(path: "api/scadenze/\(id)", method: "PATCH")
        request.httpBody = try JSONEncoder().encode(mutation)
        _ = try await execute(request)
        return try await fetchDeadline(id: id)
    }

    func completeDeadline(id: Int, request completion: DeadlineCompletionRequest) async throws -> DeadlineDTO {
        var request = authenticatedRequest(path: "api/scadenze/\(id)/completa", method: "POST")
        request.httpBody = try JSONEncoder().encode(completion)
        _ = try await execute(request)
        return try await fetchDeadline(id: id)
    }

    func reopenDeadline(id: Int) async throws -> DeadlineDTO {
        let request = authenticatedRequest(path: "api/scadenze/\(id)/riapri", method: "POST")
        _ = try await execute(request)
        return try await fetchDeadline(id: id)
    }

    func deleteDeadline(id: Int) async throws {
        let request = authenticatedRequest(path: "api/scadenze/\(id)", method: "DELETE")
        _ = try await execute(request)
    }

    func fetchLoans() async throws -> [LoanDTO] {
        let data = try await execute(authenticatedRequest(path: "api/prestiti"))
        if let response = try? JSONDecoder().decode(LoansResponse.self, from: data) {
            guard response.ok else { throw APIError.serverRejected }
            return response.loans
        }
        if let loans = try? JSONDecoder().decode([LoanDTO].self, from: data) {
            return loans
        }
        throw APIError.invalidResponse
    }

    func fetchLoan(id: Int) async throws -> LoanDTO {
        let data = try await execute(authenticatedRequest(path: "api/prestiti/\(id)"))
        if let response = try? JSONDecoder().decode(LoanResponse.self, from: data) {
            guard response.ok else { throw APIError.serverRejected }
            return response.loan
        }
        if let loan = try? JSONDecoder().decode(LoanDTO.self, from: data) {
            return loan
        }
        throw APIError.invalidResponse
    }

    func createLoan(_ mutation: LoanMutation) async throws -> LoanDTO {
        var request = authenticatedRequest(path: "api/prestiti", method: "POST")
        request.httpBody = try JSONEncoder().encode(mutation)
        let data = try await execute(request)
        return try await savedLoan(from: data)
    }

    func updateLoan(id: Int, mutation: LoanMutation) async throws -> LoanDTO {
        var request = authenticatedRequest(path: "api/prestiti/\(id)", method: "PATCH")
        request.httpBody = try JSONEncoder().encode(mutation)
        let data = try await execute(request)
        if let response = try? JSONDecoder().decode(LoanSaveResponse.self, from: data),
           response.ok, response.saved != false, let loan = response.loan {
            return loan
        }
        return try await fetchLoan(id: id)
    }

    func payLoanInstallment(id: Int, request payment: LoanPaymentRequest) async throws -> LoanDTO {
        var request = authenticatedRequest(path: "api/prestiti/\(id)/paga-rata", method: "POST")
        request.httpBody = try JSONEncoder().encode(payment)
        _ = try await execute(request)
        return try await fetchLoan(id: id)
    }

    func importPastLoanInstallments(id: Int) async throws -> LoanDTO {
        let request = authenticatedRequest(path: "api/prestiti/\(id)/importa-rate-passate", method: "POST")
        _ = try await execute(request)
        return try await fetchLoan(id: id)
    }

    func deleteLoan(id: Int) async throws {
        let request = authenticatedRequest(path: "api/prestiti/\(id)", method: "DELETE")
        _ = try await execute(request)
    }

    private func savedLoan(from data: Data) async throws -> LoanDTO {
        let response = try JSONDecoder().decode(LoanSaveResponse.self, from: data)
        guard response.ok, response.saved != false else { throw APIError.serverRejected }
        if let loan = response.loan { return loan }
        if let id = response.id { return try await fetchLoan(id: id) }
        throw APIError.invalidResponse
    }

    private func authenticatedRequest(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent(path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func execute(_ originalRequest: URLRequest, requiresAuthentication: Bool = true) async throws -> Data {
        var request = originalRequest
        request.timeoutInterval = request.timeoutInterval > 0 ? request.timeoutInterval : 15
        if requiresAuthentication {
            guard !token.isEmpty else { throw APIError.missingToken }
            request.setValue(token, forHTTPHeaderField: "x-api-token")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = object["error"] as? [String: Any],
                   let message = error["message"] as? String, !message.isEmpty {
                    throw APIError.serverMessage(message, status: httpResponse.statusCode)
                }
                if let message = object["error"] as? String, !message.isEmpty {
                    throw APIError.serverMessage(message, status: httpResponse.statusCode)
                }
                if let message = object["message"] as? String, !message.isEmpty {
                    throw APIError.serverMessage(message, status: httpResponse.statusCode)
                }
            }
            throw APIError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct NewMovement: Encodable {
    let transactionUUID: String
    let userID: Int
    let paymentDate: String
    let amount: Decimal
    let currency: String
    let merchant: String
    let appleCategory: String?
    let categoryID: Int?
    let paymentMethod: String
    let card: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case transactionUUID = "transaction_uuid"
        case userID = "user_id"
        case paymentDate = "data_pagamento"
        case amount = "importo"
        case currency = "valuta"
        case merchant = "esercente"
        case appleCategory = "categoria_apple"
        case categoryID = "categoria_id"
        case paymentMethod = "metodo_pagamento"
        case card = "carta"
        case note
    }
}

private struct NewMerchantRule: Encodable {
    let keyword: String
    let categoryID: Int

    enum CodingKeys: String, CodingKey {
        case keyword
        case categoryID = "categoria_id"
    }
}

struct MovementResponse: Decodable {
    let ok: Bool
    let saved: Bool?
    let transactionUUID: String?

    enum CodingKeys: String, CodingKey {
        case ok, saved
        case transactionUUID = "transaction_uuid"
    }
}

private struct SaveResponse: Decodable {
    let ok: Bool
    let saved: Bool
}

enum DeadlineListStatus: String, CaseIterable, Identifiable {
    case open = "aperte"
    case completed = "completate"
    case cancelled = "annullate"
    case all = "tutte"

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Aperte"
        case .completed: "Completate"
        case .cancelled: "Annullate"
        case .all: "Tutte"
        }
    }
}

struct DeadlineDTO: Decodable, Identifiable {
    let id: Int
    let uuid: String?
    let title: String
    let description: String?
    let dueDate: String
    let amount: FlexibleDecimal?
    let currency: String?
    let userID: Int
    let user: String?
    let categoryID: Int?
    let category: String?
    let status: String
    let priority: String?
    let notes: String?
    let reminderDays: [Int]?
    let recurrence: DeadlineRecurrence?
    let movementID: Int?
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?

    var dueDateValue: Date? { Self.dateOnlyFormatter.date(from: dueDate) }
    var isOpen: Bool { status == "aperta" }
    var isCompleted: Bool { status == "completata" }
    var isOverdue: Bool {
        guard isOpen, let dueDateValue else { return false }
        return dueDateValue < Calendar.current.startOfDay(for: .now)
    }

    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case uuid = "scadenza_uuid"
        case title = "titolo"
        case description = "descrizione"
        case dueDate = "data_scadenza"
        case amount = "importo"
        case currency = "valuta"
        case userID = "utente_id"
        case user = "utente"
        case categoryID = "categoria_id"
        case category = "categoria"
        case status = "stato"
        case priority = "priorita"
        case notes = "note"
        case reminderDays = "promemoria_giorni"
        case recurrence = "ricorrenza"
        case movementID = "movimento_id"
        case completedAt = "completata_il"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DeadlineRecurrence: Codable, Hashable {
    let type: String
    let interval: Int
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case type = "tipo"
        case interval = "intervallo"
        case endDate = "fine"
    }
}

struct DeadlineMutation: Encodable {
    let uuid: String
    let title: String
    let description: String?
    let dueDate: String
    let amount: Decimal?
    let currency: String
    let userID: Int
    let categoryID: Int?
    let priority: String
    let notes: String?
    let reminderDays: [Int]
    let recurrence: DeadlineRecurrence?

    enum CodingKeys: String, CodingKey {
        case uuid = "scadenza_uuid"
        case title = "titolo"
        case description = "descrizione"
        case dueDate = "data_scadenza"
        case amount = "importo"
        case currency = "valuta"
        case userID = "utente_id"
        case categoryID = "categoria_id"
        case priority = "priorita"
        case notes = "note"
        case reminderDays = "promemoria_giorni"
        case recurrence = "ricorrenza"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        if description == nil { try container.encodeNil(forKey: .description) }
        try container.encode(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(amount, forKey: .amount)
        if amount == nil { try container.encodeNil(forKey: .amount) }
        try container.encode(currency, forKey: .currency)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        if categoryID == nil { try container.encodeNil(forKey: .categoryID) }
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(notes, forKey: .notes)
        if notes == nil { try container.encodeNil(forKey: .notes) }
        try container.encode(reminderDays, forKey: .reminderDays)
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        if recurrence == nil { try container.encodeNil(forKey: .recurrence) }
    }
}

struct DeadlineCompletionRequest: Encodable {
    let completedAt: String
    let createsMovement: Bool
    let movement: DeadlineMovementPayload?

    enum CodingKeys: String, CodingKey {
        case completedAt = "completata_il"
        case createsMovement = "crea_movimento"
        case movement = "movimento"
    }
}

struct DeadlineMovementPayload: Encodable {
    let transactionUUID: String
    let paymentDate: String
    let amount: Decimal
    let currency: String
    let merchant: String
    let paymentMethod: String
    let card: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case transactionUUID = "transaction_uuid"
        case paymentDate = "data_pagamento"
        case amount = "importo"
        case currency = "valuta"
        case merchant = "esercente"
        case paymentMethod = "metodo_pagamento"
        case card = "carta"
        case note
    }
}

private struct DeadlinesResponse: Decodable {
    let ok: Bool
    let deadlines: [DeadlineDTO]

    enum CodingKeys: String, CodingKey {
        case ok
        case deadlines = "scadenze"
    }
}

private struct DeadlineResponse: Decodable {
    let ok: Bool
    let deadline: DeadlineDTO

    enum CodingKeys: String, CodingKey {
        case ok
        case deadline = "scadenza"
    }
}

private struct DeadlineSaveResponse: Decodable {
    let ok: Bool
    let saved: Bool
    let deadline: DeadlineDTO

    enum CodingKeys: String, CodingKey {
        case ok, saved
        case deadline = "scadenza"
    }
}

enum LoanListStatus: String, CaseIterable, Identifiable {
    case active
    case completed
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "Attivi"
        case .completed: "Estinti"
        case .all: "Tutti"
        }
    }
}

struct LoanDTO: Decodable, Identifiable {
    let id: Int
    let title: String
    let lender: String?
    let borrower: String?
    let type: String?
    let totalAmount: Decimal
    let installmentAmount: Decimal?
    let remainingAmountFromServer: Decimal?
    let currency: String
    let totalInstallments: Int?
    let paidInstallments: Int
    let startDate: String?
    let nextPaymentDate: String?
    let dueDay: Int?
    let frequency: String?
    let interestRate: Decimal?
    let userID: Int?
    let user: String?
    let categoryID: Int?
    let category: String?
    let paymentMethod: String?
    let card: String?
    let status: String
    let notes: String?
    let createdAt: String?
    let updatedAt: String?

    var isCompleted: Bool {
        let normalized = status.lowercased()
        return ["estinto", "estinta", "completato", "completata", "chiuso", "chiusa", "pagato", "pagata"].contains(normalized)
            || (totalInstallments.map { paidInstallments >= $0 } ?? false)
    }

    var remainingInstallments: Int? {
        totalInstallments.map { max($0 - paidInstallments, 0) }
    }

    var remainingAmount: Decimal {
        if let remainingAmountFromServer { return max(remainingAmountFromServer, 0) }
        guard let installmentAmount else { return isCompleted ? 0 : totalAmount }
        return max(totalAmount - (installmentAmount * Decimal(paidInstallments)), 0)
    }

    var progress: Double {
        guard let totalInstallments, totalInstallments > 0 else {
            guard totalAmount > 0 else { return isCompleted ? 1 : 0 }
            let paid = totalAmount - remainingAmount
            return min(max(NSDecimalNumber(decimal: paid / totalAmount).doubleValue, 0), 1)
        }
        return min(max(Double(paidInstallments) / Double(totalInstallments), 0), 1)
    }

    var startDateValue: Date? { startDate.flatMap(Self.parseDate) }
    var nextPaymentDateValue: Date? {
        if let nextPaymentDate, let explicit = Self.parseDate(nextPaymentDate) { return explicit }
        guard let startDateValue, !isCompleted else { return nil }
        return Calendar.current.date(byAdding: .month, value: paidInstallments, to: startDateValue)
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        if let date = DeadlineDTO.dateOnlyFormatter.date(from: String(rawValue.prefix(10))) { return date }
        return ISO8601DateFormatter().date(from: rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title = "titolo"
        case name = "nome"
        case description = "descrizione"
        case lender = "creditore"
        case institution = "istituto"
        case borrower = "debitore"
        case beneficiary = "beneficiario"
        case type = "tipo"
        case totalAmount = "importo_totale"
        case amount = "importo"
        case principal = "capitale"
        case installmentAmount = "importo_rata"
        case monthlyInstallment = "rata_mensile"
        case installment = "rata"
        case remainingAmount = "importo_residuo"
        case residual = "residuo"
        case totalInstallments = "numero_rate"
        case installmentsTotal = "rate_totali"
        case paidInstallments = "rate_pagate"
        case installmentsPaid = "numero_rate_pagate"
        case startDate = "data_inizio"
        case nextPaymentDate = "data_prossima_rata"
        case nextDueDate = "prossima_scadenza"
        case dueDay = "giorno_scadenza"
        case paymentDay = "giorno_pagamento"
        case frequency = "frequenza"
        case interestRate = "tasso_interesse"
        case rate = "tasso"
        case currency = "valuta"
        case userID = "utente_id"
        case user = "utente"
        case categoryID = "categoria_id"
        case category = "categoria"
        case paymentMethod = "metodo_pagamento"
        case card = "carta"
        case status = "stato"
        case notes = "note"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func string(_ keys: [CodingKeys]) -> String? {
            for key in keys {
                if let value = try? container.decode(String.self, forKey: key), !value.isEmpty { return value }
            }
            return nil
        }

        func integer(_ keys: [CodingKeys]) -> Int? {
            for key in keys {
                if let value = try? container.decode(Int.self, forKey: key) { return value }
                if let raw = try? container.decode(String.self, forKey: key), let value = Int(raw) { return value }
            }
            return nil
        }

        func decimal(_ keys: [CodingKeys]) -> Decimal? {
            for key in keys {
                if let value = try? container.decode(Decimal.self, forKey: key) { return value }
                if let raw = try? container.decode(String.self, forKey: key),
                   let value = Decimal(string: raw.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) {
                    return value
                }
            }
            return nil
        }

        guard let decodedID = integer([.id]) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: decoder.codingPath, debugDescription: "ID prestito mancante"))
        }

        id = decodedID
        title = string([.title, .name, .description]) ?? "Prestito #\(decodedID)"
        lender = string([.lender, .institution])
        borrower = string([.borrower, .beneficiary])
        type = string([.type])
        totalAmount = decimal([.totalAmount, .amount, .principal]) ?? 0
        installmentAmount = decimal([.installmentAmount, .monthlyInstallment, .installment])
        remainingAmountFromServer = decimal([.remainingAmount, .residual])
        currency = string([.currency])?.uppercased() ?? "EUR"
        totalInstallments = integer([.totalInstallments, .installmentsTotal])
        paidInstallments = integer([.paidInstallments, .installmentsPaid]) ?? 0
        startDate = string([.startDate])
        nextPaymentDate = string([.nextPaymentDate, .nextDueDate])
        dueDay = integer([.dueDay, .paymentDay])
        frequency = string([.frequency])
        interestRate = decimal([.interestRate, .rate])
        userID = integer([.userID])
        user = string([.user])
        categoryID = integer([.categoryID])
        category = string([.category])
        paymentMethod = string([.paymentMethod])
        card = string([.card])
        status = string([.status]) ?? "attivo"
        notes = string([.notes])
        createdAt = string([.createdAt])
        updatedAt = string([.updatedAt])
    }
}

struct LoanMutation: Encodable {
    let title: String
    let lender: String?
    let borrower: String?
    let type: String
    let totalAmount: Decimal
    let installmentAmount: Decimal
    let currency: String
    let totalInstallments: Int
    let paidInstallments: Int
    let startDate: String
    let dueDay: Int
    let frequency: String
    let interestRate: Decimal?
    let userID: Int
    let categoryID: Int?
    let paymentMethod: String?
    let card: String?
    let status: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case title = "titolo"
        case lender = "creditore"
        case borrower = "debitore"
        case type = "tipo"
        case totalAmount = "importo_totale"
        case installmentAmount = "importo_rata"
        case currency = "valuta"
        case totalInstallments = "numero_rate"
        case paidInstallments = "rate_pagate"
        case startDate = "data_inizio"
        case dueDay = "giorno_scadenza"
        case frequency = "frequenza"
        case interestRate = "tasso_interesse"
        case userID = "utente_id"
        case categoryID = "categoria_id"
        case paymentMethod = "metodo_pagamento"
        case card
        case status = "stato"
        case notes = "note"
    }
}

struct LoanPaymentRequest: Encodable {
    let paymentDate: String
    let createsMovement: Bool

    enum CodingKeys: String, CodingKey {
        case paymentDate = "data_pagamento"
        case createsMovement = "crea_movimento"
    }
}

private struct LoansResponse: Decodable {
    let ok: Bool
    let loans: [LoanDTO]

    enum CodingKeys: String, CodingKey {
        case ok
        case loans = "prestiti"
    }
}

private struct LoanResponse: Decodable {
    let ok: Bool
    let loan: LoanDTO

    enum CodingKeys: String, CodingKey {
        case ok
        case loan = "prestito"
    }
}

private struct LoanSaveResponse: Decodable {
    let ok: Bool
    let saved: Bool?
    let id: Int?
    let loan: LoanDTO?

    enum CodingKeys: String, CodingKey {
        case ok, saved, id
        case loan = "prestito"
    }
}

private struct MovementsResponse: Decodable {
    let ok: Bool
    let movements: [ServerMovement]

    enum CodingKeys: String, CodingKey {
        case ok
        case movements = "movimenti"
    }
}

struct ServerMovement: Decodable, Identifiable {
    let id: Int
    let paymentDate: String
    let user: String
    let amount: FlexibleDecimal
    let currency: String?
    let merchant: String?
    let category: String?
    let paymentMethod: String?
    let card: String?
    let deductible730: Int?
    let deductibleType: String?
    let note: String?

    var paymentDateValue: Date? {
        if let date = Self.fractionalDateFormatter.date(from: paymentDate) { return date }
        return ISO8601DateFormatter().date(from: paymentDate)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case paymentDate = "data_pagamento"
        case user = "utente"
        case amount = "importo"
        case currency = "valuta"
        case merchant = "esercente"
        case category = "categoria"
        case paymentMethod = "metodo_pagamento"
        case card = "carta"
        case deductible730 = "detraibile_730"
        case deductibleType = "tipo_730"
        case note
    }
}

private struct CategoriesResponse: Decodable {
    let ok: Bool
    let categories: [ExpenseCategory]

    enum CodingKeys: String, CodingKey {
        case ok
        case categories = "categorie"
    }
}

struct ExpenseCategory: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let parentID: Int?
    let monthlyBudget: FlexibleDecimal?
    let active: Int?

    var isActive: Bool { active != 0 }

    enum CodingKeys: String, CodingKey {
        case id
        case name = "nome"
        case parentID = "parent_id"
        case monthlyBudget = "budget_mensile"
        case active = "attiva"
    }
}

private struct MerchantRulesResponse: Decodable {
    let ok: Bool
    let rules: [MerchantRuleDTO]

    enum CodingKeys: String, CodingKey {
        case ok
        case rules = "regole"
    }
}

struct MerchantRuleDTO: Decodable, Identifiable {
    let id: Int
    let keyword: String
    let categoryID: Int
    let category: String?
    let deductible730: Int?
    let deductibleType: String?
    let active: Int?

    enum CodingKeys: String, CodingKey {
        case id, keyword, category
        case categoryID = "categoria_id"
        case deductible730 = "detraibile_730"
        case deductibleType = "tipo_730"
        case active = "attiva"
    }
}

struct MonthlyReport: Decodable {
    let ok: Bool
    let year: Int
    let month: Int
    let total: FlexibleDecimal
    let categories: [CategoryTotal]
    let users: [UserTotal]
    let deductibles: [DeductibleTotal]

    enum CodingKeys: String, CodingKey {
        case ok
        case year = "anno"
        case month = "mese"
        case total = "totale"
        case categories = "categorie"
        case users = "utenti"
        case deductibles = "detraibili"
    }
}

struct CategoryTotal: Decodable, Identifiable {
    let category: String
    let total: FlexibleDecimal
    var id: String { category }

    enum CodingKeys: String, CodingKey {
        case category = "categoria"
        case total = "totale"
    }
}

struct UserTotal: Decodable, Identifiable {
    let user: String
    let total: FlexibleDecimal
    var id: String { user }

    enum CodingKeys: String, CodingKey {
        case user = "utente"
        case total = "totale"
    }
}

struct DeductibleTotal: Decodable, Identifiable {
    let type: String
    let total: FlexibleDecimal
    var id: String { type }

    enum CodingKeys: String, CodingKey {
        case type = "tipo_730"
        case total = "totale"
    }
}

struct FlexibleDecimal: Decodable, Hashable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
        } else if let string = try? container.decode(String.self),
                  let decimal = Decimal(string: string.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) {
            value = decimal
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Valore monetario non valido")
        }
    }
}

enum APIError: LocalizedError {
    case invalidConfiguration
    case missingToken
    case invalidResponse
    case httpStatus(Int)
    case serverMessage(String, status: Int)
    case serverRejected

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Configura URL, token e ID utente nelle Impostazioni."
        case .missingToken: "Il token API non è configurato."
        case .invalidResponse: "La risposta del server non è valida."
        case .httpStatus(401), .httpStatus(403): "Token API non valido o non autorizzato."
        case .httpStatus(let status): "Il server ha risposto con errore HTTP \(status)."
        case .serverMessage(let message, _): message
        case .serverRejected: "Il server non ha accettato la richiesta."
        }
    }
}
