import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WhoopService.self) private var whoopService
    @Environment(HealthKitService.self) private var healthKitService
    @Environment(HealthAutoExportService.self) private var healthAutoExportService
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius

    @State private var showingClearConfirmation = false
    @State private var sampleDataLoaded = false
    @State private var labDataImported = false

    // Import/Export
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importExportMessage = ""
    @State private var showingImportResult = false

    // API Key
    @State private var claudeAPIKey = ""
    @State private var showingAPIKeyField = false

    var body: some View {
        Form {
            Section("Units") {
                Picker("Weight", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
                Picker("Temperature", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
            }

            Section("Integrations") {
                whoopSection
                #if os(iOS)
                appleHealthSection
                #else
                healthAutoExportSection
                #endif
                claudeAPISection
            }

            Section("Data") {
                Button {
                    LabDataSeeder.importAllLabs(into: modelContext)
                    labDataImported = true
                } label: {
                    Label("Import Lab Results", systemImage: "cross.vial")
                }
                .disabled(labDataImported)

                Button {
                    exportData()
                } label: {
                    Label("Export All Data", systemImage: "arrow.up.doc")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Import Data", systemImage: "arrow.down.doc")
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

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear All Data", systemImage: "trash.fill")
                }
                .confirmationDialog("Clear all data?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                    Button("Clear Everything", role: .destructive) {
                        SampleDataService.clearAllData(from: modelContext)
                        sampleDataLoaded = false
                    }
                } message: {
                    Text("This will delete all measurements, medications, habits, biomarkers, conditions, and diet plans.")
                }
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

    // MARK: - WHOOP Section

    private var whoopSection: some View {
        Group {
            HStack {
                Label {
                    Text("WHOOP")
                        .font(.body)
                } icon: {
                    Image(systemName: "heart.circle.fill")
                        .foregroundStyle(.green)
                }

                Spacer()

                if whoopService.isConnected {
                    StatusBadge(label: "Connected", color: .green)
                } else {
                    StatusBadge(label: "Not Connected", color: .secondary)
                }
            }

            if whoopService.isConnected {
                // Sync button with progress
                HStack {
                    Button {
                        Task { await whoopService.syncData(into: modelContext) }
                    } label: {
                        if whoopService.isSyncing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                if let progress = whoopService.syncProgress {
                                    Text("Syncing \(progress.phase)... (\(progress.imported) imported)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(whoopService.isSyncing)

                    Spacer()

                    Button("Disconnect", role: .destructive) {
                        whoopService.disconnect()
                    }
                    .font(.caption)
                }

                if let lastSync = whoopService.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                Button {
                    whoopService.startOAuth()
                } label: {
                    Label("Connect WHOOP", systemImage: "link")
                }
            }

            if let error = whoopService.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
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
                        .foregroundStyle(.red)
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
                HStack {
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

                    Spacer()

                    Button("Disconnect", role: .destructive) {
                        healthKitService.disconnect()
                    }
                    .font(.caption)
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
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Health Auto Export Section

    private var healthAutoExportSection: some View {
        Group {
            HStack {
                Label {
                    Text("Apple Health")
                        .font(.body)
                } icon: {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.red)
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
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Claude API Section

    private var claudeAPISection: some View {
        Group {
            HStack {
                Label {
                    Text("Claude API")
                        .font(.body)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
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
                        .textFieldStyle(.roundedBorder)
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
