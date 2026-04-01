import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportExportView

struct ImportExportView: View {
    @State private var vm = UnifiedImportExportService.shared
    @State private var loginVM = LoginViewModel.shared
    @State private var cardVM = PPSRAutomationViewModel.shared
    @State private var historyService = ExportHistoryService.shared
    let logger = DebugLogger.shared

    @State private var selectedTab: ImportExportTab = .importData
    @State private var selectedExportFormat: ExportFormat = .json
    @State private var selectedDataType: DataType = .credentials
    @State private var showingFilePicker = false
    @State private var showingExportShare = false
    @State private var exportData: Data?
    @State private var exportFilename: String = ""
    @State private var detectedFormat: ImportFormat?
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    private enum ImportExportTab: String, CaseIterable {
        case importData = "Import"
        case exportData = "Export"
    }

    private enum DataType: String, CaseIterable {
        case credentials = "Credentials"
        case cards = "Cards"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                Divider()

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .importData:
                            importSection
                        case .exportData:
                            exportSection
                        }
                        historySection
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import / Export")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .dropDestination(for: Data.self) { items, _ in
                guard let data = items.first else { return false }
                handleDroppedData(data)
                return true
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Mode", selection: $selectedTab) {
            ForEach(ImportExportTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(spacing: 14) {
            // Data type picker
            dataTypePicker

            // File picker button / drop zone
            dropZoneButton

            // Detected format
            if let format = detectedFormat {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                    Text("Detected: \(format.rawValue)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Progress
            if vm.isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: vm.importProgress, total: 1.0)
                        .tint(.blue)
                    Text("\(Int(vm.importProgress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Result summary
            if let result = vm.lastImportResult {
                importResultCard(result)
            }

            // Status message
            if let message = statusMessage {
                statusBanner(message: message, isError: statusIsError)
            }
        }
    }

    private var dropZoneButton: some View {
        Button {
            showingFilePicker = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text("Select File or Drop Here")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("Supports JSON, CSV, pipe-delimited")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.blue.opacity(0.4))
            )
        }
        .disabled(vm.isImporting)
    }

    private func importResultCard(_ result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: result.failureCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.failureCount == 0 ? .green : .orange)
                Text("Import Complete")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text(result.format.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Divider()

            HStack(spacing: 20) {
                statPill(label: "Added", value: "\(result.successCount)", color: .green)
                statPill(label: "Dupes", value: "\(result.duplicateCount)", color: .yellow)
                statPill(label: "Failed", value: "\(result.failureCount)", color: .red)
            }

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Errors:")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                    ForEach(result.errors.prefix(5), id: \.self) { error in
                        Text("• \(error)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if result.errors.count > 5 {
                        Text("+ \(result.errors.count - 5) more...")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(spacing: 14) {
            dataTypePicker

            // Format picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                Picker("Format", selection: $selectedExportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Data summary
            dataSummaryRow

            // Export button
            Button {
                performExport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export \(selectedDataType.rawValue)")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(currentDataCount == 0)
            .opacity(currentDataCount == 0 ? 0.4 : 1.0)
            .sheet(isPresented: $showingExportShare) {
                if let data = exportData {
                    ShareSheetView(data: data, filename: exportFilename)
                }
            }

            if let message = statusMessage {
                statusBanner(message: message, isError: statusIsError)
            }
        }
    }

    private var dataSummaryRow: some View {
        HStack {
            Image(systemName: selectedDataType == .credentials ? "key.fill" : "creditcard.fill")
                .foregroundStyle(.blue)
            Text("\(currentDataCount) \(selectedDataType.rawValue.lowercased()) available")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                if !historyService.records.isEmpty {
                    Button("Clear") {
                        historyService.clearHistory()
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                }
            }

            if historyService.records.isEmpty {
                Text("No import/export history yet")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(historyService.records.prefix(10), id: \.id) { record in
                    HStack(spacing: 10) {
                        Image(systemName: record.exportType.contains("import") ? "square.and.arrow.down" : "square.and.arrow.up")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exportType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("\(record.format) • \(record.cardCount) items")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.date, style: .relative)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared Components

    private var dataTypePicker: some View {
        Picker("Data Type", selection: $selectedDataType) {
            ForEach(DataType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? .red : .green)
            Spacer()
        }
        .padding(12)
        .background((isError ? Color.red : Color.green).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Computed Properties

    private var currentDataCount: Int {
        switch selectedDataType {
        case .credentials: loginVM.credentials.count
        case .cards: cardVM.cards.count
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                showStatus("Cannot access file", isError: true)
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                performImport(data: data)
            } catch {
                showStatus("Failed to read file: \(error.localizedDescription)", isError: true)
            }
        case .failure(let error):
            showStatus("File picker error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleDroppedData(_ data: Data) {
        detectedFormat = vm.detectFormat(from: data)
        performImport(data: data)
    }

    private func performImport(data: Data) {
        let format = vm.detectFormat(from: data)
        detectedFormat = format
        statusMessage = nil

        Task {
            let result: ImportResult
            switch selectedDataType {
            case .credentials:
                result = await vm.importCredentials(from: data, format: format)
            case .cards:
                result = await vm.importCards(from: data, format: format)
            }

            if result.successCount > 0 {
                triggerHaptic(.success)
                showStatus("Imported \(result.successCount) \(selectedDataType.rawValue.lowercased())", isError: false)
            } else {
                triggerHaptic(.error)
                showStatus("Import completed with no new items", isError: true)
            }
        }
    }

    private func performExport() {
        let data: Data?
        let ext: String

        switch selectedDataType {
        case .credentials:
            data = vm.exportCredentials(format: selectedExportFormat)
        case .cards:
            data = vm.exportCards(format: selectedExportFormat)
        }

        switch selectedExportFormat {
        case .json: ext = "json"
        case .csv: ext = "csv"
        case .pipeDelimited: ext = "txt"
        }

        guard let exportedData = data else {
            showStatus("No data to export", isError: true)
            triggerHaptic(.error)
            return
        }

        exportData = exportedData
        exportFilename = "\(selectedDataType.rawValue.lowercased())_export.\(ext)"
        showingExportShare = true

        ExportHistoryService.shared.recordExport(
            format: selectedExportFormat.rawValue,
            cardCount: currentDataCount,
            exportType: "\(selectedDataType.rawValue.lowercased())_export"
        )

        triggerHaptic(.success)
        showStatus("Export ready for sharing", isError: false)
        logger.log("Exported \(currentDataCount) \(selectedDataType.rawValue.lowercased()) as \(selectedExportFormat.rawValue)", category: .general, level: .info, detail: nil, sessionId: nil, durationMs: nil, metadata: nil)
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(4))
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - ShareSheetView

private struct ShareSheetView: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ImportExportView()
        .preferredColorScheme(.dark)
}
