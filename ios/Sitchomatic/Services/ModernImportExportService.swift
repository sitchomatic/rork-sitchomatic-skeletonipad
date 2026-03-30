import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modern Import/Export Service

@MainActor
final class ModernImportExportService {
    nonisolated(unsafe) static let shared = ModernImportExportService()

    private let logger = DebugLogger.shared

    enum ImportFormat: String {
        case csv = "CSV"
        case json = "JSON"
        case pipeDelimited = "Pipe-Delimited"
        case auto = "Auto-Detect"
    }

    enum ExportFormat: String {
        case json = "JSON"
        case csv = "CSV"
        case structuredArchive = "Structured Archive"
    }

    nonisolated struct ImportResult: Sendable {
        let credentials: [LoginCredential]
        let validCount: Int
        let invalidCount: Int
        let errors: [String]
        let format: ImportFormat
    }

    nonisolated struct ExportResult: Sendable {
        let data: Data
        let filename: String
        let format: ExportFormat
    }

    private init() {
        logger.log("ModernImportExportService: initialized", category: .automation, level: .info)
    }

    // MARK: - Import

    func importCredentials(from data: Data, format: ImportFormat = .auto) async -> ImportResult {
        let detectedFormat = format == .auto ? await detectFormat(data: data) : format

        logger.log("ModernImportExportService: importing as \(detectedFormat.rawValue)", category: .automation, level: .info)

        switch detectedFormat {
        case .csv:
            return await importCSV(data: data)
        case .json:
            return await importJSON(data: data)
        case .pipeDelimited:
            return await importPipeDelimited(data: data)
        case .auto:
            // Fallback
            return await importCSV(data: data)
        }
    }

    func importCredentialsFromFile(url: URL) async -> ImportResult {
        guard let data = try? Data(contentsOf: url) else {
            return ImportResult(credentials: [], validCount: 0, invalidCount: 0, errors: ["Failed to read file"], format: .auto)
        }

        return await importCredentials(from: data, format: .auto)
    }

    func validateCredential(username: String, password: String) -> (valid: Bool, error: String?) {
        // Basic validation
        if username.isEmpty {
            return (false, "Username is empty")
        }

        if password.isEmpty {
            return (false, "Password is empty")
        }

        if !username.contains("@") {
            return (false, "Username must be an email address")
        }

        if password.count < 4 {
            return (false, "Password too short")
        }

        return (true, nil)
    }

    // MARK: - Export

    func exportCredentials(_ credentials: [LoginCredential], format: ExportFormat = .structuredArchive) async -> ExportResult? {
        logger.log("ModernImportExportService: exporting \(credentials.count) credentials as \(format.rawValue)", category: .automation, level: .info)

        switch format {
        case .json:
            return await exportJSON(credentials: credentials)
        case .csv:
            return await exportCSV(credentials: credentials)
        case .structuredArchive:
            return await exportStructuredArchive(credentials: credentials)
        }
    }

    // MARK: - Private Implementation

    private func detectFormat(data: Data) async -> ImportFormat {
        guard let text = String(data: data, encoding: .utf8) else {
            return .csv
        }

        let firstLine = text.components(separatedBy: .newlines).first ?? ""

        // Check for JSON
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return .json
        }

        // Check for pipe-delimited
        if firstLine.contains("|") {
            return .pipeDelimited
        }

        // Default to CSV
        return .csv
    }

    private func importCSV(data: Data) async -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) else {
            return ImportResult(credentials: [], validCount: 0, invalidCount: 0, errors: ["Invalid encoding"], format: .csv)
        }

        var credentials: [LoginCredential] = []
        var errors: [String] = []
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }

            let components = line.components(separatedBy: ",")
            guard components.count >= 2 else {
                errors.append("Line \(index + 1): Invalid format")
                continue
            }

            let username = components[0].trimmingCharacters(in: .whitespaces)
            let password = components[1].trimmingCharacters(in: .whitespaces)

            let validation = validateCredential(username: username, password: password)
            if !validation.valid {
                errors.append("Line \(index + 1): \(validation.error ?? "Invalid")")
                continue
            }

            let credential = LoginCredential(username: username, password: password, alias: nil)
            credentials.append(credential)
        }

        return ImportResult(
            credentials: credentials,
            validCount: credentials.count,
            invalidCount: errors.count,
            errors: errors,
            format: .csv
        )
    }

    private func importJSON(data: Data) async -> ImportResult {
        var credentials: [LoginCredential] = []
        var errors: [String] = []

        do {
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for (index, dict) in array.enumerated() {
                    guard let username = dict["username"] as? String,
                          let password = dict["password"] as? String else {
                        errors.append("Entry \(index + 1): Missing username or password")
                        continue
                    }

                    let validation = validateCredential(username: username, password: password)
                    if !validation.valid {
                        errors.append("Entry \(index + 1): \(validation.error ?? "Invalid")")
                        continue
                    }

                    let alias = dict["alias"] as? String
                    let credential = LoginCredential(username: username, password: password, alias: alias)
                    credentials.append(credential)
                }
            }
        } catch {
            errors.append("JSON parsing error: \(error.localizedDescription)")
        }

        return ImportResult(
            credentials: credentials,
            validCount: credentials.count,
            invalidCount: errors.count,
            errors: errors,
            format: .json
        )
    }

    private func importPipeDelimited(data: Data) async -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) else {
            return ImportResult(credentials: [], validCount: 0, invalidCount: 0, errors: ["Invalid encoding"], format: .pipeDelimited)
        }

        var credentials: [LoginCredential] = []
        var errors: [String] = []
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }

            let components = line.components(separatedBy: "|")
            guard components.count >= 2 else {
                errors.append("Line \(index + 1): Invalid format")
                continue
            }

            let username = components[0].trimmingCharacters(in: .whitespaces)
            let password = components[1].trimmingCharacters(in: .whitespaces)

            let validation = validateCredential(username: username, password: password)
            if !validation.valid {
                errors.append("Line \(index + 1): \(validation.error ?? "Invalid")")
                continue
            }

            let credential = LoginCredential(username: username, password: password, alias: nil)
            credentials.append(credential)
        }

        return ImportResult(
            credentials: credentials,
            validCount: credentials.count,
            invalidCount: errors.count,
            errors: errors,
            format: .pipeDelimited
        )
    }

    private func exportJSON(credentials: [LoginCredential]) async -> ExportResult? {
        let array = credentials.map { cred in
            [
                "username": cred.username,
                "password": cred.password,
                "alias": cred.alias ?? "",
                "status": cred.status.rawValue,
                "testCount": cred.testResults.count,
            ] as [String : Any]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "sitchomatic_credentials_\(timestamp).json"

        return ExportResult(data: data, filename: filename, format: .json)
    }

    private func exportCSV(credentials: [LoginCredential]) async -> ExportResult? {
        var csv = "Username,Password,Alias,Status,TestCount\n"

        for cred in credentials {
            csv += "\(cred.username),\(cred.password),\(cred.alias ?? ""),\(cred.status.rawValue),\(cred.testResults.count)\n"
        }

        guard let data = csv.data(using: .utf8) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "sitchomatic_credentials_\(timestamp).csv"

        return ExportResult(data: data, filename: filename, format: .csv)
    }

    private func exportStructuredArchive(credentials: [LoginCredential]) async -> ExportResult? {
        let archive: [String: Any] = [
            "version": "2.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "totalCredentials": credentials.count,
            "credentials": credentials.map { cred in
                [
                    "username": cred.username,
                    "password": cred.password,
                    "alias": cred.alias ?? "",
                    "status": cred.status.rawValue,
                    "testResults": cred.testResults.map { result in
                        [
                            "outcome": result.outcome,
                            "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                            "latencyMs": result.latencyMs,
                        ] as [String : Any]
                    },
                ] as [String : Any]
            },
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: archive, options: .prettyPrinted) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "sitchomatic_archive_\(timestamp).json"

        return ExportResult(data: data, filename: filename, format: .structuredArchive)
    }
}

// MARK: - Modern Import View

struct ModernImportView: View {
    @State private var importService = ModernImportExportService.shared
    @State private var isImporting = false
    @State private var importResult: ModernImportExportService.ImportResult?
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Import Credentials")
                .font(.title2.bold())

            if let result = importResult {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Imported \(result.validCount) credentials")
                            .font(.headline)
                    }

                    if result.invalidCount > 0 {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("\(result.invalidCount) invalid entries")
                                .font(.subheadline)
                        }

                        ForEach(Array(result.errors.prefix(10)), id: \.self) { error in
                            Text("• \(error)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }

            Button(action: {
                showFilePicker = true
            }) {
                Label("Select File to Import", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(isImporting)

            if isImporting {
                ProgressView("Importing...")
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await handleFileImport(result: result)
            }
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) async {
        isImporting = true

        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let imported = await importService.importCredentialsFromFile(url: url)
            importResult = imported

            // Add to credentials list
            for credential in imported.credentials {
                LoginViewModel.shared.credentials.append(credential)
            }

            isImporting = false
        } catch {
            isImporting = false
            importResult = ModernImportExportService.ImportResult(
                credentials: [],
                validCount: 0,
                invalidCount: 0,
                errors: [error.localizedDescription],
                format: .auto
            )
        }
    }
}
