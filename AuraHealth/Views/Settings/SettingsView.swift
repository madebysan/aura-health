import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage("aiProvider") private var aiProvider: AIProvider = .anthropic
    @AppStorage("aiModel") private var aiModelID = AIProviderCatalog.defaultModelID(for: .anthropic)

    @State private var showingClearConfirmation = false
    @State private var sampleDataLoaded = false

    // Import/Export
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var showingImportOptions = false
    @State private var importExportMessage = ""
    @State private var showingImportResult = false

    // AI provider setup
    @State private var providerAPIKey = ""
    @State private var showingAPIKeyField = false
    @State private var providerHasKey = false
    @State private var consentGranted = false

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
                appleHealthSection
            }

            Section("AI") {
                aiProviderSection
                apiKeySection
                modelPickerSection
                consentSection
            }

            Section("Data") {
                Button {
                    exportData()
                } label: {
                    Label("Create Complete Backup", systemImage: "arrow.up.doc")
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
                        clearAllData()
                    }
                } message: {
                    Text("This permanently deletes Aura's local health records, documents, conversations, API keys, and preferences. It does not delete data from Apple Health.")
                }
            }

            Section("Privacy & Support") {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }

                Link(destination: URL(string: "mailto:hi@santiagoalonso.com?subject=Aura%20Health%20Support")!) {
                    Label("Contact Support", systemImage: "envelope")
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
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
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
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .confirmationDialog("Import Aura Data", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Merge with Existing Data") {
                performImport(mode: .merge)
            }
            Button("Replace Existing Data", role: .destructive) {
                performImport(mode: .replace)
            }
            Button("Cancel", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("Merge adds records that are not already present. Replace first clears the current local database. Create a backup before replacing data.")
        }
        .alert("Aura Data", isPresented: $showingImportResult) {
            Button("OK") {}
        } message: {
            Text(importExportMessage)
        }
        .onAppear {
            refreshAISetupState()
        }
        .onChange(of: aiProvider) {
            aiModelID = AIProviderCatalog.defaultModelID(for: aiProvider)
            providerAPIKey = ""
            showingAPIKeyField = false
            refreshAISetupState()
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

                if healthKitService.hasRequestedAccess {
                    StatusBadge(label: "Access Requested", color: .green)
                } else if healthKitService.isAvailable {
                    StatusBadge(label: "Available", color: .secondary)
                } else {
                    StatusBadge(label: "Not Available", color: .secondary)
                }
            }

            if healthKitService.hasRequestedAccess {
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
                    healthKitService.stopSyncing()
                } label: {
                    Label {
                        Text("Stop Syncing Apple Health")
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if let lastSync = healthKitService.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                Text("Manage individual permissions in Settings → Health → Data Access & Devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - AI Provider

    private var aiProviderSection: some View {
        Picker(selection: $aiProvider) {
            ForEach(AIProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        } label: {
            Label("Provider", systemImage: "network")
        }
    }

    private var apiKeySection: some View {
        Group {
            HStack {
                Label("\(aiProvider.displayName) API Key", systemImage: "key")
                Spacer()

                if providerHasKey {
                    StatusBadge(label: "Stored", color: .green)
                    Button("Remove", role: .destructive) {
                        AIKeyStore.removeValue(for: aiProvider)
                        providerHasKey = false
                        consentGranted = false
                    }
                    .font(.caption)
                } else {
                    Button("Add Key") { showingAPIKeyField.toggle() }
                }
            }

            if showingAPIKeyField {
                HStack {
                    SecureField(aiProvider.keyPlaceholder, text: $providerAPIKey)
                        .textContentType(.password)
                    Button("Save") {
                        let trimmed = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if AIKeyStore.setValue(trimmed, for: aiProvider) {
                            providerAPIKey = ""
                            providerHasKey = true
                            showingAPIKeyField = false
                        }
                    }
                    .disabled(providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

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

            Picker("", selection: $aiModelID) {
                ForEach(AIProviderCatalog.models(for: aiProvider)) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var consentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { consentGranted },
                set: { value in
                    consentGranted = value
                    if value {
                        AIConsentStore().grant(for: aiProvider)
                    } else {
                        AIConsentStore().revoke(for: aiProvider)
                    }
                }
            )) {
                Text("Allow AI processing")
            }

            Text("When you explicitly send a message or attachment, Aura shares that content and health records returned by its read tools for that request with \(aiProvider.displayName). Nothing is sent automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Read \(aiProvider.displayName)'s privacy policy", destination: aiProvider.privacyPolicyURL)
                .font(.caption)
        }
    }

    private func refreshAISetupState() {
        providerHasKey = AIKeyStore.value(for: aiProvider) != nil
        consentGranted = AIConsentStore().hasConsent(for: aiProvider)
        aiModelID = AIProviderCatalog.model(id: aiModelID, provider: aiProvider).id
    }

    // MARK: - Export

    private func exportData() {
        do {
            let data = try ImportExportService.exportAllData(from: modelContext)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = "aura-health-\(formatter.string(from: Date())).json"

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
                pendingImportData = try Data(contentsOf: url)
                showingImportOptions = true
            } catch {
                importExportMessage = "Import failed: \(error.localizedDescription)"
                showingImportResult = true
            }
        case .failure(let error):
            importExportMessage = "Failed to select file: \(error.localizedDescription)"
            showingImportResult = true
        }
    }

    private func performImport(mode: ImportExportService.ImportMode) {
        guard let data = pendingImportData else { return }
        defer { pendingImportData = nil }

        do {
            let result = try ImportExportService.importData(data, into: modelContext, mode: mode)
            importExportMessage = result.summary
        } catch {
            importExportMessage = "Import failed: \(error.localizedDescription)"
        }
        showingImportResult = true
    }

    private func clearAllData() {
        do {
            try DataLifecycleService.clearAllUserData(from: modelContext)
            sampleDataLoaded = false
            importExportMessage = "All local Aura data and credentials were deleted."
        } catch {
            importExportMessage = "Aura could not delete all data: \(error.localizedDescription)"
        }
        showingImportResult = true
    }
}
