import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case tracking
    case vitals
    case conditions
    case medications
    case biomarkers
    case vault
    case chat
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking: "Habits"
        case .vitals: "Vitals"
        case .conditions: "Health Profile"
        case .medications: "Meds and Supplements"
        case .biomarkers: "Labs"
        case .vault: "Vault"
        case .chat: "Chat"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .tracking: "ph.list-checks"
        case .vitals: "ph.heartbeat"
        case .conditions: "ph.stethoscope"
        case .medications: "ph.pill"
        case .biomarkers: "ph.test-tube"
        case .vault: "ph.vault"
        case .chat: "ph.chats"
        case .settings: "ph.gear"
        }
    }

    var iconColor: Color {
        switch self {
        case .tracking: .orange
        case .vitals: .pink
        case .conditions: .purple
        case .medications: .blue
        case .biomarkers: .green
        case .vault: .gray
        case .chat: .cyan
        case .settings: .gray
        }
    }

    static let tabBarSections: [AppSection] = [.vitals, .tracking, .biomarkers, .chat]

    /// A section from a link or tool name. Diet now lives on the Health profile.
    static func named(_ name: String) -> AppSection? {
        name == "diet" ? .conditions : AppSection(rawValue: name)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @State private var selectedSection: AppSection
    @State private var chatPrefill: String?

    init() {
        #if DEBUG
        let requestedSection = UserDefaults.standard.string(forKey: "ScreenshotSection")
            .flatMap(AppSection.init(rawValue:))
        _selectedSection = State(initialValue: requestedSection ?? .vitals)
        #else
        _selectedSection = State(initialValue: .vitals)
        #endif
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            ForEach(AppSection.tabBarSections) { section in
                NavigationStack {
                    if section == .chat {
                        ChatView(prefillMessage: $chatPrefill)
                    } else {
                        DetailView(section: section)
                    }
                }
                .tabItem {
                    Label(section.label, image: section.iconName)
                }
                .tag(section)
            }
            MoreMenuView(selectedSection: $selectedSection, chatPrefill: $chatPrefill)
                .tabItem {
                    Label("More", image: "ph.dots-three")
                }
                .tag(AppSection.settings)
        }
        .tint(Notebook.ink)
        .onReceive(NotificationCenter.default.publisher(for: .switchToChat)) { notification in
            if let prefill = notification.object as? String {
                chatPrefill = prefill
            }
            selectedSection = .chat
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notification in
            // Sections without a tab live under More (tagged .settings); MoreMenuView opens them.
            if let section = notification.object as? AppSection {
                selectedSection = AppSection.tabBarSections.contains(section) ? section : .settings
            }
        }
        .task { await autoSync() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await autoSync() }
        }
    }

    /// Auto-sync connected services (debounced — skip if synced within last 15 minutes)
    private func autoSync() async {
        let fifteenMinutes: TimeInterval = 15 * 60

        if healthKitService.hasRequestedAccess && !healthKitService.isSyncing {
            let shouldSync = healthKitService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await healthKitService.syncData(into: modelContext)
            }
        }
    }
}

// MARK: - More Menu (iOS)

struct MoreMenuView: View {
    @Binding var selectedSection: AppSection
    @Binding var chatPrefill: String?
    @State private var navigationPath = NavigationPath()
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

    // The tab bar covers Vitals, Habits, Biomarkers and Chat. Settings sits apart, below.
    private let sections: [AppSection] = [.conditions, .medications, .vault]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sections, content: moreRow)
                    moreRow(.settings)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
            }
            .notebookBackground()
            .navigationTitle("More")
            .navigationDestination(for: AppSection.self) { section in
                DetailView(section: section)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notification in
            if let section = notification.object as? AppSection, !AppSection.tabBarSections.contains(section) {
                navigationPath = NavigationPath([section])
            }
        }
    }

    /// One ruled row: ink glyph, label, chevron.
    private func moreRow(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            HStack(spacing: 14) {
                Image(section.iconName)
                    .font(.body)
                    .foregroundStyle(Notebook.ink)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Text(section.label)
                    .foregroundStyle(Notebook.ink)
                Spacer()
                Image("ph.caret-right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Notebook.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Router

struct DetailView: View {
    let section: AppSection
    @Binding var chatPrefill: String?

    init(section: AppSection, chatPrefill: Binding<String?> = .constant(nil)) {
        self.section = section
        self._chatPrefill = chatPrefill
    }

    var body: some View {
        view(for: section)
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func view(for section: AppSection) -> some View {
        switch section {
        case .tracking:     HabitsView()
        case .vitals:       VitalsView()
        case .conditions:   ConditionsView()
        case .medications:  MedicationsView()
        case .biomarkers:   BiomarkersView()
        case .vault:        VaultView()
        case .chat:         ChatView(prefillMessage: $chatPrefill)
        case .settings:     SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Measurement.self, Medication.self, MedicationLog.self,
            Biomarker.self, Habit.self, HabitLog.self,
            Condition.self, DietPlan.self, MetricRange.self,
            VaultDocument.self, HealthMemory.self, Conversation.self,
            LabSession.self
        ], inMemory: true)
}
