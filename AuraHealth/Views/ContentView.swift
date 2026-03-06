import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case trends
    case biomarkers
    case medications
    case adherence
    case habits
    case conditions
    case vault
    case chat
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .trends: "Trends"
        case .biomarkers: "Biomarkers"
        case .medications: "Medications"
        case .adherence: "Adherence"
        case .habits: "Habits"
        case .conditions: "Conditions"
        case .vault: "Vault"
        case .chat: "Chat"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .today: "heart.text.square.fill"
        case .trends: "chart.xyaxis.line"
        case .biomarkers: "cross.vial.fill"
        case .medications: "pills.fill"
        case .adherence: "checkmark.circle.fill"
        case .habits: "repeat"
        case .conditions: "stethoscope"
        case .vault: "lock.doc.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .settings: "gearshape.fill"
        }
    }

    static let tabBarSections: [AppSection] = [.today, .trends, .biomarkers, .medications, .habits]
}

struct ContentView: View {
    @State private var selectedSection: AppSection = .today

    var body: some View {
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
}

// MARK: - Sidebar (macOS)

#if os(macOS)
struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section("Health") {
                sidebarItem(.today)
                sidebarItem(.trends)
                sidebarItem(.biomarkers)
            }

            Section("Tracking") {
                sidebarItem(.medications)
                sidebarItem(.adherence)
                sidebarItem(.habits)
                sidebarItem(.conditions)
            }

            Section("Tools") {
                sidebarItem(.vault)
                sidebarItem(.chat)
            }

            Section {
                sidebarItem(.settings)
            }
        }
        .navigationTitle("Aura")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private func sidebarItem(_ section: AppSection) -> some View {
        Label(section.label, systemImage: section.iconName)
            .tag(section)
    }
}
#endif

// MARK: - More Menu (iOS)

struct MoreMenuView: View {
    @Binding var selection: AppSection

    private let moreSections: [AppSection] = [
        .adherence, .conditions, .vault, .chat, .settings
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
        case .today: TodayView()
        case .trends: TrendsView()
        case .biomarkers: BiomarkersView()
        case .medications: MedicationsView()
        case .adherence: AdherenceView()
        case .habits: HabitsView()
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
