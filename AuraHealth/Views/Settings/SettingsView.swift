import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius

    @State private var showingChangePassword = false
    @State private var showingClearConfirmation = false
    @State private var sampleDataLoaded = false

    // Import/Export
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importExportMessage = ""
    @State private var showingImportResult = false

    // API Key
    @State private var claudeAPIKey = ""
    @State private var showingAPIKeyField = false

    // Integration services
    @State private var whoopService = WhoopService()
    @State private var healthKitService = HealthKitService()

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
                // WHOOP
                HStack {
                    Label("WHOOP", systemImage: "heart.circle.fill")
                    Spacer()
                    if whoopService.isConnected {
                        StatusBadge(label: "Connected", color: .green)
                        Button("Sync") {
                            Task { await whoopService.syncData(into: modelContext) }
                        }
                        .disabled(whoopService.isSyncing)
                        Button("Disconnect", role: .destructive) {
                            whoopService.disconnect()
                        }
                        .foregroundStyle(.red)
                    } else {
                        StatusBadge(label: "Not Connected", color: .secondary)
                    }
                }
                if let lastSync = whoopService.lastSyncDate {
                    Text("Last synced: \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let error = whoopService.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                // Apple Health
                HStack {
                    Label("Apple Health", systemImage: "heart.text.square")
                    Spacer()
                    if healthKitService.isAuthorized {
                        StatusBadge(label: "Connected", color: .green)
                        Button("Sync") {
                            Task { await healthKitService.syncData(into: modelContext) }
                        }
                        .disabled(healthKitService.isSyncing)
                    } else if healthKitService.isAvailable {
                        Button("Connect") {
                            Task { await healthKitService.requestAuthorization() }
                        }
                    } else {
                        Text("Not Available")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let lastSync = healthKitService.lastSyncDate {
                    Text("Last synced: \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let error = healthKitService.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                // Claude API
                HStack {
                    Label("Claude API", systemImage: "sparkles")
                    Spacer()
                    if KeychainService.getValue(for: "claude-api-key") != nil {
                        StatusBadge(label: "Configured", color: .green)
                        Button("Remove") {
                            KeychainService.deleteValue(for: "claude-api-key")
                        }
                        .foregroundStyle(.red)
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

            Section("Vault") {
                if KeychainService.hasVaultPassword {
                    Button("Change Vault Password") { showingChangePassword = true }
                }
            }

            Section("Data") {
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
        .navigationTitle("Settings")
        .sheet(isPresented: $showingChangePassword) { ChangePasswordSheet() }
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

// MARK: - Change Password

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Current Password", text: $currentPassword)
                SecureField("New Password", text: $newPassword)
                SecureField("Confirm New Password", text: $confirmPassword)
                if !error.isEmpty {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Change Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 250)
        #endif
    }

    private func save() {
        guard KeychainService.verifyVaultPassword(currentPassword) else { error = "Current password is incorrect"; return }
        guard newPassword == confirmPassword else { error = "New passwords don't match"; return }
        guard newPassword.count >= 4 else { error = "Minimum 4 characters"; return }
        if KeychainService.saveVaultPassword(newPassword) { dismiss() }
        else { error = "Failed to save new password" }
    }
}
