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
    #if os(macOS)
    @Environment(HealthAutoExportService.self) private var healthAutoExportService
    #endif
    @State private var selectedSection: AppSection = .vitals
    @State private var showingChat = false
    @State private var chatPrefill: String?

    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                SidebarView(selection: $selectedSection)
            } detail: {
                DetailView(section: selectedSection, chatPrefill: $chatPrefill)
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
                // More tab — remaining sections presented as a grouped list
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
            #endif
        }
        #if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            if showingChat {
                FloatingChatPanel(isShowing: $showingChat)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
                    ))
            } else {
                FloatingChatButton(isShowingChat: $showingChat)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(AppAnimation.expand, value: showingChat)
        #endif
        // switchToChat is handled by MoreMenuView on iOS, macOS uses floating panel
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

        if healthKitService.isAuthorized && !healthKitService.isSyncing {
            let shouldSync = healthKitService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await healthKitService.syncData(into: modelContext)
            }
        }

        #if os(macOS)
        if healthAutoExportService.isEnabled && !healthAutoExportService.isSyncing {
            let shouldSync = healthAutoExportService.lastSyncDate.map { Date().timeIntervalSince($0) > fifteenMinutes } ?? true
            if shouldSync {
                await healthAutoExportService.syncData(into: modelContext)
            }
        }
        #endif
    }
}

// MARK: - Sidebar (macOS)

#if os(macOS)
struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Top-level items (no section header)
                ForEach([AppSection.vitals, .tracking]) { section in
                    sidebarRow(section)
                        .padding(.horizontal, 8)
                }

                sidebarSection("Health", items: [.correlations, .conditions, .medications, .biomarkers, .diet])
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

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
                    #if os(iOS)
                    .toolbar(.hidden, for: .tabBar)
                    #endif
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
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
