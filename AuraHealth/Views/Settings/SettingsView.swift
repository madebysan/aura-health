import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    #if os(macOS)
    // Health Auto Export reads files from iCloud Drive via NSOpenPanel — macOS only
    @Environment(HealthAutoExportService.self) private var healthAutoExportService
    #endif
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage("claudeModel") private var claudeModel: ClaudeModel = .sonnet

    @State private var showingClearConfirmation = false
    @State private var sampleDataLoaded = false

    // Import/Export
    @State private var showingImporter = false
    @State private var importExportMessage = ""
    @State private var showingImportResult = false

    // API Key
    @State private var claudeAPIKey = ""
    @State private var showingAPIKeyField = false

    var body: some View {
        Form {
            Section("Units") {
                HStack {
                    Text("Weight")
                    Spacer()
                    PillSegmentedPicker(
                        options: WeightUnit.allCases,
                        selection: $weightUnit,
                        label: { $0.symbol }
                    )
                    .fixedSize()
                }

                HStack {
                    Text("Temperature")
                    Spacer()
                    PillSegmentedPicker(
                        options: TemperatureUnit.allCases,
                        selection: $temperatureUnit,
                        label: { $0.symbol }
                    )
                    .fixedSize()
                }
            }

            Section("Apple Health") {
                #if os(iOS)
                appleHealthSection
                #endif
                #if os(macOS)
                healthAutoExportSection
                #endif
            }

            Section("AI") {
                claudeAPISection
                modelPickerSection
            }

            Section("Data") {
                Button {
                    exportData()
                } label: {
                    Label("Export Aura Data", systemImage: "arrow.up.doc")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Import Aura Data", systemImage: "arrow.down.doc")
                }

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear All Data", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }
                .confirmationDialog("Clear all data?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                    Button("Clear Everything", role: .destructive) {
                        SampleDataService.clearAllData(from: modelContext)
                        sampleDataLoaded = false
                    }
                } message: {
                    Text("This will delete all measurements, medications, habits, biomarkers, conditions, and diet plans.")
                }
            }

            #if DEBUG
            Section {
                Button {
                    SampleDataService.loadSampleData(into: modelContext)
                    sampleDataLoaded = true
                } label: {
                    Label("Load Sample Data", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(sampleDataLoaded)
            } header: {
                Text("Developer")
            }
            #endif

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0").foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://santiagoalonso.com")!) {
                    HStack {
                        Text("Made by").foregroundStyle(.secondary)
                        Text("santiagoalonso.com").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK") {}
        } message: {
            Text(importExportMessage)
        }
    }

    // MARK: - Apple Health Section

    private var appleHealthSection: some View {
        Group {
            HStack {
                Label {
                    Text("Apple Health")
                        .font(.body)
                } icon: {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.blue)
                }

                Spacer()

                if healthKitService.isAuthorized {
                    StatusBadge(label: "Connected", color: .green)
                } else if healthKitService.isAvailable {
                    StatusBadge(label: "Available", color: .secondary)
                } else {
                    StatusBadge(label: "Not Available", color: .secondary)
                }
            }

            if healthKitService.isAuthorized {
                Button {
                    Task { await healthKitService.syncData(into: modelContext) }
                } label: {
                    if healthKitService.isSyncing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            if let progress = healthKitService.syncProgress {
                                Text("Syncing \(progress.phase)... (\(progress.imported) imported)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(healthKitService.isSyncing)

                Button(role: .destructive) {
                    healthKitService.disconnect()
                } label: {
                    Label {
                        Text("Disconnect Apple Health")
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if let lastSync = healthKitService.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else if healthKitService.isAvailable {
                Button {
                    Task { await healthKitService.requestAuthorization() }
                } label: {
                    Label("Connect Apple Health", systemImage: "link")
                }
            }

            if let error = healthKitService.error {
                InlineErrorBanner(message: error)
            }
        }
    }

    // MARK: - Health Auto Export Section

    #if os(macOS)
    private var healthAutoExportSection: some View {
        Group {
            HStack {
                Label {
                    Text("Apple Health")
                        .font(.body)
                } icon: {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.blue)
                }

                Spacer()

                if healthAutoExportService.isEnabled {
                    StatusBadge(label: "Connected", color: .green)
                } else {
                    StatusBadge(label: "Not Found", color: .secondary)
                }
            }

            if healthAutoExportService.isEnabled {
                HStack {
                    Button {
                        Task { await healthAutoExportService.syncData(into: modelContext) }
                    } label: {
                        if healthAutoExportService.isSyncing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                if let progress = healthAutoExportService.syncProgress {
                                    Text("Syncing \(progress.phase)... (\(progress.imported) imported)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(healthAutoExportService.isSyncing)

                    Spacer()

                    Button("Disconnect", role: .destructive) {
                        healthAutoExportService.disconnect()
                    }
                    .font(.caption)
                }

                if let lastSync = healthAutoExportService.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                Text("Via Health Auto Export → iCloud Drive")
                    .font(.caption2).foregroundStyle(.quaternary)
            } else {
                Button {
                    healthAutoExportService.pickFolder()
                } label: {
                    Label("Connect Apple Health", systemImage: "link")
                }

                Text("Requires Health Auto Export on iPhone syncing to iCloud Drive.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error = healthAutoExportService.error {
                InlineErrorBanner(message: error)
            }
        }
    }
    #endif

    // MARK: - Claude API Section

    private var claudeAPISection: some View {
        Group {
            HStack {
                Label {
                    Text("Claude API")
                        .font(.body)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                }

                Spacer()

                if KeychainService.getValue(for: "claude-api-key") != nil {
                    StatusBadge(label: "Configured", color: .green)
                    Button("Remove") {
                        KeychainService.deleteValue(for: "claude-api-key")
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                } else {
                    Button("Add Key") { showingAPIKeyField.toggle() }
                }
            }
            if showingAPIKeyField {
                HStack {
                    SecureField("sk-ant-...", text: $claudeAPIKey)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Button("Save") {
                        if !claudeAPIKey.isEmpty {
                            KeychainService.setValue(claudeAPIKey, for: "claude-api-key")
                            claudeAPIKey = ""
                            showingAPIKeyField = false
                        }
                    }
                    .disabled(claudeAPIKey.isEmpty)
                }
            }
        }
    }

    // MARK: - Model Picker

    private var modelPickerSection: some View {
        HStack {
            Label {
                Text("Model")
                    .font(.body)
            } icon: {
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
            }

            Spacer()

            Picker("", selection: $claudeModel) {
                ForEach(ClaudeModel.allCases, id: \.self) { model in
                    VStack(alignment: .leading) {
                        Text(model.displayName)
                    }
                    .tag(model)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Export

    private func exportData() {
        do {
            let data = try ImportExportService.exportAllData(from: modelContext)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = "aura-health-\(formatter.string(from: Date())).json"

            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileName
            panel.allowedContentTypes = [.json]
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    try? data.write(to: url)
                    importExportMessage = "Data exported successfully."
                    showingImportResult = true
                }
            }
            #else
            // iOS: use share sheet
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController { topVC = presented }
                activityVC.popoverPresentationController?.sourceView = topVC.view
                topVC.present(activityVC, animated: true)
            }
            #endif
        } catch {
            importExportMessage = "Export failed: \(error.localizedDescription)"
            showingImportResult = true
        }
    }

    // MARK: - Import

    private func importFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let importResult = try ImportExportService.importData(data, into: modelContext)
                importExportMessage = importResult.summary
                showingImportResult = true
            } catch {
                importExportMessage = "Import failed: \(error.localizedDescription)"
                showingImportResult = true
            }
        case .failure(let error):
            importExportMessage = "Failed to select file: \(error.localizedDescription)"
            showingImportResult = true
        }
    }
}
