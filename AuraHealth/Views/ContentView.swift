import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case vitals
    case correlations
    case biomarkers
    case medications
    case tracking
    case conditions
    case vault
    case chat
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vitals: "Vitals"
        case .correlations: "Correlations"
        case .biomarkers: "Biomarkers"
        case .medications: "Medications"
        case .tracking: "Tracking"
        case .conditions: "Conditions"
        case .vault: "Vault"
        case .chat: "Chat"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .vitals: "heart.text.square.fill"
        case .correlations: "chart.xyaxis.line"
        case .biomarkers: "cross.vial.fill"
        case .medications: "pills.fill"
        case .tracking: "checkmark.rectangle.stack.fill"
        case .conditions: "stethoscope"
        case .vault: "lock.doc.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .settings: "gearshape.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .vitals: .pink
        case .correlations: .indigo
        case .biomarkers: .green
        case .medications: .blue
        case .tracking: .orange
        case .conditions: .purple
        case .vault: .gray
        case .chat: .cyan
        case .settings: .gray
        }
    }

    static let tabBarSections: [AppSection] = [.vitals, .correlations, .biomarkers, .medications, .tracking]
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WhoopService.self) private var whoopService
    @Environment(HealthKitService.self) private var healthKitService
    @Environment(HealthAutoExportService.self) private var healthAutoExportService
    @State private var selectedSection: AppSection = .vitals
    @State private var showingChat = false

    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                SidebarView(selection: $selectedSection)
            } detail: {
                DetailView(section: selectedSection)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notification in
                if let section = notification.object as? AppSection {
                    withAnimation(AppAnimation.viewSwitch) {
                        selectedSection = section
                    }
                }
            }
            #else
            TabView(selection: $selectedSection) {
                ForEach(AppSection.tabBarSections) { section in
                    NavigationStack {
                        DetailView(section: section)
                    }
                    .tabItem {
                        Label(section.label, systemImage: section.iconName)
                    }
                    .tag(section)
                }
                NavigationStack {
                    MoreMenuView(selection: $selectedSection)
                }
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(AppSection.settings)
            }
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            if selectedSection != .chat {
                FloatingChatButton(isShowingChat: $showingChat)
            }
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack {
                ChatView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingChat = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 540, minHeight: 500, idealHeight: 650)
            #endif
        }
        .task { await autoSync() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await autoSync() }
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await autoSync() }
        }
        #endif
    }

    /// Auto-sync connected services (debounced — skip if synced within last 15 minutes)
    private func autoSync() async {
        let fifteenMinutes: TimeInterval = 15 * 60

        if whoopService.isConnected && !whoopService.isSyncing {
            let shouldSync = whoopService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await whoopService.syncData(into: modelContext)
            }
        }

        if healthKitService.isAuthorized && !healthKitService.isSyncing {
            let shouldSync = healthKitService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await healthKitService.syncData(into: modelContext)
            }
        }

        if healthAutoExportService.isEnabled && !healthAutoExportService.isSyncing {
            let shouldSync = healthAutoExportService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await healthAutoExportService.syncData(into: modelContext)
            }
        }
    }
}

// MARK: - Sidebar (macOS)

#if os(macOS)
struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSection("Health", items: [.vitals, .correlations, .biomarkers])
                sidebarSection("Tracking", items: [.medications, .tracking, .conditions])
                sidebarSection("Tools", items: [.vault, .chat])
                Divider().padding(.horizontal, 12).padding(.vertical, 4)
                sidebarRow(.settings)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Aura")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private func sidebarSection(_ title: String, items: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 2)

            ForEach(items) { section in
                sidebarRow(section)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            withAnimation(AppAnimation.viewSwitch) {
                selection = section
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? section.iconColor : section.iconColor.opacity(0.7))
                    .frame(width: 20)

                Text(section.label)
                    .font(.body)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color(.controlBackgroundColor) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .shadow(color: isSelected ? .black.opacity(0.04) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}
#endif

// MARK: - More Menu (iOS)

struct MoreMenuView: View {
    @Binding var selection: AppSection

    private let moreSections: [AppSection] = [
        .conditions, .vault, .chat, .settings
    ]

    var body: some View {
        List {
            ForEach(moreSections) { section in
                NavigationLink {
                    DetailView(section: section)
                } label: {
                    Label(section.label, systemImage: section.iconName)
                }
            }
        }
        .navigationTitle("More")
    }
}

// MARK: - Detail Router

struct DetailView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .vitals: VitalsView()
        case .correlations: CorrelationsView()
        case .biomarkers: BiomarkersView()
        case .medications: MedicationsView()
        case .tracking: HabitsView()
        case .conditions: ConditionsView()
        case .vault: VaultView()
        case .chat: ChatView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Measurement.self, Medication.self, MedicationLog.self,
            Biomarker.self, Habit.self, HabitLog.self,
            Condition.self, DietPlan.self, MetricRange.self,
            VaultDocument.self, HealthMemory.self, Conversation.self
        ], inMemory: true)
}
