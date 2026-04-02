import Foundation
import Observation

// MARK: - Import/Export Enums & Structs

nonisolated enum ImportFormat: String, CaseIterable, Sendable {
    case csv = "CSV"
    case json = "JSON"
    case pipeDelimited = "Pipe-Delimited"
    case auto = "Auto-Detect"
}

nonisolated enum ExportFormat: String, CaseIterable, Sendable {
    case json = "JSON"
    case csv = "CSV"
    case pipeDelimited = "Pipe-Delimited"
}

nonisolated struct ImportResult: Sendable {
    let successCount: Int
    let failureCount: Int
    let errors: [String]
    let duplicateCount: Int
    let format: ImportFormat

    var totalProcessed: Int { successCount + failureCount + duplicateCount }
    var summary: String {
        "\(successCount) imported, \(duplicateCount) duplicates, \(failureCount) failed (\(format.rawValue))"
    }
}

nonisolated struct LoginCredentialImport: Sendable {
    let email: String
    let password: String
    let url: String?
}

nonisolated struct PPSRCardImport: Sendable {
    let cardNumber: String
    let name: String
    let expiry: String
    let cvv: String
}

nonisolated enum ImportableItem: Sendable {
    case credentials([LoginCredentialImport])
    case cards([PPSRCardImport])
}

// MARK: - UnifiedImportExportService

@Observable
@MainActor
class UnifiedImportExportService {
    static let shared = UnifiedImportExportService()

    let logger = DebugLogger.shared

    var isImporting: Bool = false
    var importProgress: Double = 0.0
    var lastImportResult: ImportResult?

    private init() {}

    // MARK: - Format Detection

    nonisolated func detectFormat(from data: Data) -> ImportFormat {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .auto
        }

        if text.hasPrefix("{") || text.hasPrefix("[") {
            return .json
        }

        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        if firstLine.contains("|") && !firstLine.contains(",") {
            return .pipeDelimited
        }
        if firstLine.contains(",") {
            return .csv
        }

        return .auto
    }

    // MARK: - Import Credentials

    func importCredentials(from data: Data, format: ImportFormat) async -> ImportResult {
        isImporting = true
        importProgress = 0.0

        let resolvedFormat = format == .auto ? detectFormat(from: data) : format
        var imported: [LoginCredentialImport] = []
        var errors: [String] = []

        guard let text = String(data: data, encoding: .utf8) else {
            let result = ImportResult(successCount: 0, failureCount: 0, errors: ["Unable to decode data as UTF-8"], duplicateCount: 0, format: resolvedFormat)
            isImporting = false
            lastImportResult = result
            return result
        }

        switch resolvedFormat {
        case .json:
            (imported, errors) = parseCredentialsJSON(text)
        case .csv:
            (imported, errors) = parseCredentialsDelimited(text, delimiter: ",")
        case .pipeDelimited:
            (imported, errors) = parseCredentialsDelimited(text, delimiter: "|")
        case .auto:
            errors.append("Could not auto-detect format")
        }

        importProgress = 0.5

        let (valid, validationErrors) = validateCredentials(imported)
        errors.append(contentsOf: validationErrors)

        let existingEmails = Set(LoginViewModel.shared.credentials.map { $0.username.lowercased() })
        var duplicateCount = 0
        var added: [LoginCredentialImport] = []

        for (index, cred) in valid.enumerated() {
            if existingEmails.contains(cred.email.lowercased()) {
                duplicateCount += 1
            } else {
                added.append(cred)
            }
            importProgress = 0.5 + 0.5 * Double(index + 1) / Double(valid.count)
        }

        let newCredentials = added.map { item in
            LoginCredential(
                username: item.email,
                password: item.password
            )
        }
        LoginViewModel.shared.credentials.append(contentsOf: newCredentials)

        let result = ImportResult(
            successCount: added.count,
            failureCount: errors.count,
            errors: errors,
            duplicateCount: duplicateCount,
            format: resolvedFormat
        )

        logger.log("Imported credentials: \(result.summary)", category: .system, level: .info, detail: nil, sessionId: nil, durationMs: nil, metadata: nil)
        ExportHistoryService.shared.recordExport(format: resolvedFormat.rawValue, cardCount: added.count, exportType: "credential_import")

        isImporting = false
        lastImportResult = result
        return result
    }

    // MARK: - Import Cards

    func importCards(from data: Data, format: ImportFormat) async -> ImportResult {
        isImporting = true
        importProgress = 0.0

        let resolvedFormat = format == .auto ? detectFormat(from: data) : format
        var imported: [PPSRCardImport] = []
        var errors: [String] = []

        guard let text = String(data: data, encoding: .utf8) else {
            let result = ImportResult(successCount: 0, failureCount: 0, errors: ["Unable to decode data as UTF-8"], duplicateCount: 0, format: resolvedFormat)
            isImporting = false
            lastImportResult = result
            return result
        }

        switch resolvedFormat {
        case .json:
            (imported, errors) = parseCardsJSON(text)
        case .csv:
            (imported, errors) = parseCardsDelimited(text, delimiter: ",")
        case .pipeDelimited:
            (imported, errors) = parseCardsDelimited(text, delimiter: "|")
        case .auto:
            errors.append("Could not auto-detect format")
        }

        importProgress = 0.5

        let existingNumbers = Set(PPSRAutomationViewModel.shared.cards.map { $0.number })
        var duplicateCount = 0
        var added: [PPSRCardImport] = []

        for (index, card) in imported.enumerated() {
            let stripped = card.cardNumber.replacingOccurrences(of: " ", with: "")
            if existingNumbers.contains(stripped) {
                duplicateCount += 1
            } else {
                added.append(card)
            }
            importProgress = 0.5 + 0.5 * Double(index + 1) / Double(max(imported.count, 1))
        }

        for item in added {
            if let card = PPSRCard.parseLine("\(item.cardNumber)|\(item.expiry)|\(item.cvv)") {
                PPSRAutomationViewModel.shared.cards.append(card)
            }
        }

        let result = ImportResult(
            successCount: added.count,
            failureCount: errors.count,
            errors: errors,
            duplicateCount: duplicateCount,
            format: resolvedFormat
        )

        logger.log("Imported cards: \(result.summary)", category: .system, level: .info, detail: nil, sessionId: nil, durationMs: nil, metadata: nil)
        ExportHistoryService.shared.recordExport(format: resolvedFormat.rawValue, cardCount: added.count, exportType: "card_import")

        isImporting = false
        lastImportResult = result
        return result
    }

    // MARK: - Export Credentials

    func exportCredentials(format: ExportFormat) -> Data? {
        let credentials = LoginViewModel.shared.credentials
        guard !credentials.isEmpty else { return nil }

        switch format {
        case .json:
            let items = credentials.map { cred in
                ["email": cred.username, "password": cred.password, "status": cred.status.rawValue]
            }
            return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])

        case .csv:
            var lines = ["email,password,status"]
            for cred in credentials {
                lines.append("\(escapeCSV(cred.username)),\(escapeCSV(cred.password)),\(cred.status.rawValue)")
            }
            return lines.joined(separator: "\n").data(using: .utf8)

        case .pipeDelimited:
            var lines = ["email|password|status"]
            for cred in credentials {
                lines.append("\(cred.username)|\(cred.password)|\(cred.status.rawValue)")
            }
            return lines.joined(separator: "\n").data(using: .utf8)
        }
    }

    // MARK: - Export Cards

    func exportCards(format: ExportFormat) -> Data? {
        let cards = PPSRAutomationViewModel.shared.cards
        guard !cards.isEmpty else { return nil }

        switch format {
        case .json:
            let items = cards.map { card in
                ["number": card.number, "expiryMonth": card.expiryMonth, "expiryYear": card.expiryYear, "cvv": card.cvv, "brand": card.brand.rawValue, "status": card.status.rawValue]
            }
            return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])

        case .csv:
            var lines = ["number,expiry_month,expiry_year,cvv,brand,status"]
            for card in cards {
                lines.append("\(card.number),\(card.expiryMonth),\(card.expiryYear),\(card.cvv),\(card.brand.rawValue),\(card.status.rawValue)")
            }
            return lines.joined(separator: "\n").data(using: .utf8)

        case .pipeDelimited:
            var lines = ["number|expiry_month|expiry_year|cvv|brand|status"]
            for card in cards {
                lines.append("\(card.number)|\(card.expiryMonth)|\(card.expiryYear)|\(card.cvv)|\(card.brand.rawValue)|\(card.status.rawValue)")
            }
            return lines.joined(separator: "\n").data(using: .utf8)
        }
    }

    // MARK: - Validation

    func validateCredentials(_ imports: [LoginCredentialImport]) -> (valid: [LoginCredentialImport], errors: [String]) {
        var valid: [LoginCredentialImport] = []
        var errors: [String] = []
        guard let emailRegex = try? Regex(#"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#) else {
            return ([], ["Email regex initialization failed"])
        }

        for (index, item) in imports.enumerated() {
            let trimmedEmail = item.email.trimmingCharacters(in: .whitespaces)
            if trimmedEmail.isEmpty {
                errors.append("Row \(index + 1): empty email")
            } else if trimmedEmail.wholeMatch(of: emailRegex) == nil {
                errors.append("Row \(index + 1): invalid email '\(trimmedEmail)'")
            } else if item.password.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Row \(index + 1): empty password")
            } else {
                valid.append(item)
            }
        }
        return (valid, errors)
    }

    // MARK: - Private Parsers

    private func parseCredentialsJSON(_ text: String) -> ([LoginCredentialImport], [String]) {
        var results: [LoginCredentialImport] = []
        var errors: [String] = []
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ([], ["Invalid JSON format"])
        }
        for (index, dict) in array.enumerated() {
            guard let email = dict["email"] as? String, let password = dict["password"] as? String else {
                errors.append("Row \(index + 1): missing email or password")
                continue
            }
            results.append(LoginCredentialImport(email: email, password: password, url: dict["url"] as? String))
        }
        return (results, errors)
    }

    private func parseCredentialsDelimited(_ text: String, delimiter: String) -> ([LoginCredentialImport], [String]) {
        var results: [LoginCredentialImport] = []
        var errors: [String] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let startIndex = lines.first?.lowercased().contains("email") == true ? 1 : 0

        for i in startIndex..<lines.count {
            let parts = lines[i].components(separatedBy: delimiter).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else {
                errors.append("Row \(i + 1): insufficient columns")
                continue
            }
            results.append(LoginCredentialImport(email: parts[0], password: parts[1], url: parts.count > 2 ? parts[2] : nil))
        }
        return (results, errors)
    }

    private func parseCardsJSON(_ text: String) -> ([PPSRCardImport], [String]) {
        var results: [PPSRCardImport] = []
        var errors: [String] = []
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ([], ["Invalid JSON format"])
        }
        for (index, dict) in array.enumerated() {
            guard let number = dict["cardNumber"] as? String ?? dict["number"] as? String,
                  let name = dict["name"] as? String,
                  let expiry = dict["expiry"] as? String,
                  let cvv = dict["cvv"] as? String else {
                errors.append("Row \(index + 1): missing card fields")
                continue
            }
            results.append(PPSRCardImport(cardNumber: number, name: name, expiry: expiry, cvv: cvv))
        }
        return (results, errors)
    }

    private func parseCardsDelimited(_ text: String, delimiter: String) -> ([PPSRCardImport], [String]) {
        var results: [PPSRCardImport] = []
        var errors: [String] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let startIndex = lines.first?.lowercased().contains("card") == true || lines.first?.lowercased().contains("number") == true ? 1 : 0

        for i in startIndex..<lines.count {
            let parts = lines[i].components(separatedBy: delimiter).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else {
                errors.append("Row \(i + 1): insufficient columns (need number, name, expiry, cvv)")
                continue
            }
            results.append(PPSRCardImport(cardNumber: parts[0], name: parts[1], expiry: parts[2], cvv: parts[3]))
        }
        return (results, errors)
    }

    // MARK: - Helpers

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
