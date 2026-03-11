import SwiftUI
import SwiftData

struct ClinicConnectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FHIRProviderService.self) private var fhirService
    @Environment(ClinicalRecordService.self) private var clinicalRecordService

    @State private var searchText = ""
    @State private var showingNotAvailable = false
    @State private var selectedProvider: HealthProvider?

    var body: some View {
        List {
            // Apple Health Records
            Section {
                appleHealthRecordsSection
            } header: {
                Text("Apple Health Records")
            } footer: {
                Text("Connect providers in Settings > Health > Health Records on your iPhone, then sync here.")
            }

            // Connected providers
            if !fhirService.connections.isEmpty {
                Section("Connected") {
                    ForEach(fhirService.connections) { connection in
                        connectedRow(connection)
                    }

                    if fhirService.connections.count > 0 {
                        Button {
                            Task { await fhirService.syncAllProviders(into: modelContext) }
                        } label: {
                            if fhirService.isSyncing {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(fhirService.syncProgress ?? "Syncing...")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(fhirService.isSyncing)
                    }
                }
            }

            // Provider directory search
            Section {
                if fhirService.isLoadingDirectory {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading health systems...")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(searchResults) { provider in
                        providerRow(provider)
                    }
                }
            } header: {
                HStack {
                    Text("Find Your Clinic")
                    Spacer()
                    Text("\(fhirService.providers.count) providers")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } footer: {
                Text("Search thousands of health systems, clinics, and labs. Powered by Epic's open FHIR directory.")
            }
        }
        .searchable(text: $searchText, prompt: "Search by clinic or hospital name")
        .navigationTitle("Connect Clinic")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            if fhirService.providers.isEmpty {
                await fhirService.fetchProviderDirectory()
            }
        }
        .refreshable {
            await fhirService.fetchProviderDirectory()
        }
        .alert("Not Available Yet", isPresented: $showingNotAvailable) {
            Button("OK") {}
        } message: {
            if let provider = selectedProvider {
                Text("\(provider.name) doesn't have a public FHIR endpoint yet. Try searching for your health system by name — many clinics use Epic MyChart under the hood.")
            }
        }
    }

    // MARK: - Apple Health Records

    private var appleHealthRecordsSection: some View {
        Group {
            HStack {
                Label {
                    Text("Clinical Records")
                } icon: {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundStyle(.pink)
                }
                Spacer()
                if clinicalRecordService.isAuthorized {
                    StatusBadge(label: "Enabled", color: .green)
                } else if clinicalRecordService.isAvailable {
                    StatusBadge(label: "Available", color: .secondary)
                } else {
                    StatusBadge(label: "Not Available", color: .secondary)
                }
            }

            if clinicalRecordService.isAuthorized {
                Button {
                    Task { await clinicalRecordService.syncRecords(into: modelContext) }
                } label: {
                    if clinicalRecordService.isSyncing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Syncing...").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Sync Clinical Records", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(clinicalRecordService.isSyncing)

                if let summary = clinicalRecordService.syncSummary, !clinicalRecordService.isSyncing {
                    HStack(spacing: 12) {
                        SyncStatBadge(count: summary.labResults, label: "Labs")
                        SyncStatBadge(count: summary.medications, label: "Meds")
                        SyncStatBadge(count: summary.conditions, label: "Conditions")
                        SyncStatBadge(count: summary.vitals, label: "Vitals")
                    }
                }

                if let lastSync = clinicalRecordService.lastSyncDate {
                    Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                Button(role: .destructive) {
                    clinicalRecordService.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle").foregroundStyle(.red)
                }
            } else if clinicalRecordService.isAvailable {
                Button {
                    Task { await clinicalRecordService.requestAuthorization() }
                } label: {
                    Label("Enable Clinical Records", systemImage: "link")
                }
            }

            if let error = clinicalRecordService.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Provider Row

    private func providerRow(_ provider: HealthProvider) -> some View {
        Button {
            if provider.fhirBaseURL.isEmpty {
                selectedProvider = provider
                showingNotAvailable = true
            } else {
                Task { await fhirService.connect(provider: provider) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconForProvider(provider))
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(provider.network.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if fhirService.isConnected(provider.id) {
                    StatusBadge(label: "Connected", color: .green)
                } else if provider.fhirBaseURL.isEmpty {
                    Text("Coming Soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(fhirService.isConnected(provider.id))
    }

    // MARK: - Connected Row

    private func connectedRow(_ connection: FHIRConnection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.providerName)
                    .font(.body)
                if let lastSync = connection.lastSyncDate {
                    Text("Synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text("Connected \(connection.connectedDate, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                fhirService.disconnect(providerID: connection.providerID)
            } label: {
                Text("Disconnect").font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private var searchResults: [HealthProvider] {
        let results = fhirService.searchProviders(searchText)
        return results.filter { !fhirService.isConnected($0.id) }
    }

    private func iconForProvider(_ provider: HealthProvider) -> String {
        switch provider.category {
        case .healthSystem: return "building.2.fill"
        case .clinic: return "cross.circle.fill"
        case .lab: return "flask.fill"
        case .telehealth: return "video.fill"
        }
    }
}

// MARK: - Sync Stat Badge

struct SyncStatBadge: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(count > 0 ? .primary : .tertiary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
