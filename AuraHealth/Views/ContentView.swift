import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case tracking
    case vitals
    case correlations
    case conditions
    case medications
    case biomarkers
    case diet
    case vault
    case chat
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking: "Habits"
        case .vitals: "Vitals"
        case .correlations: "Correlations"
        case .conditions: "Conditions"
        case .medications: "Medications"
        case .biomarkers: "Biomarkers"
        case .diet: "Diet"
        case .vault: "Vault"
        case .chat: "Chat"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .tracking: "checkmark.rectangle.stack.fill"
        case .vitals: "heart.text.square.fill"
        case .correlations: "chart.xyaxis.line"
        case .conditions: "stethoscope"
        case .medications: "pills.fill"
        case .biomarkers: "drop.fill"
        case .diet: "fork.knife"
        case .vault: "lock.doc.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .settings: "gearshape.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .tracking: .orange
        case .vitals: .pink
        case .correlations: .indigo
        case .conditions: .purple
        case .medications: .blue
        case .biomarkers: .green
        case .diet: .orange
        case .vault: .gray
        case .chat: .cyan
        case .settings: .gray
        }
    }

    static let tabBarSections: [AppSection] = [.vitals, .tracking, .biomarkers, .chat]
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
                    Label(section.label, systemImage: section.iconName)
                }
                .tag(section)
            }
            MoreMenuView(selectedSection: $selectedSection, chatPrefill: $chatPrefill)
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(AppSection.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToChat)) { notification in
            if let prefill = notification.object as? String {
                chatPrefill = prefill
            }
            selectedSection = .chat
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notification in
            if let section = notification.object as? AppSection {
                selectedSection = section
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

    // Grouped sections for the "More" list.
    // The tab bar covers: Vitals, Habits, Biomarkers, Chat.
    private let healthSections: [AppSection] = [.correlations, .medications, .conditions, .diet]
    private let toolSections: [AppSection]   = [.vault]
    private let appSections: [AppSection]    = [.settings]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Health") {
                    ForEach(healthSections, content: moreRow)
                }
                Section("Tools") {
                    ForEach(toolSections, content: moreRow)
                }
                Section("App") {
                    ForEach(appSections, content: moreRow)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppSection.self) { section in
                DetailView(section: section)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
    }

    /// A single row with the section's colored icon and a navigation chevron.
    @ViewBuilder
    private func moreRow(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            HStack(spacing: 14) {
                // Colored icon badge (matches iOS Settings style)
                Image(systemName: section.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(section.iconColor, in: RoundedRectangle(cornerRadius: 7))

                Text(section.label)
                    .foregroundStyle(.primary)
            }
        }
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
        case .correlations: CorrelationsView()
        case .conditions:   ConditionsView()
        case .medications:  MedicationsView()
        case .biomarkers:   BiomarkersView()
        case .diet:         DietPlansView()
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
