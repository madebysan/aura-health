import SwiftUI
import SwiftData

@main
struct AuraHealthApp: App {
    @State private var whoopService = WhoopService()
    @State private var healthKitService = HealthKitService()
    @State private var clinicalRecordService = ClinicalRecordService()
    @State private var fhirProviderService = FHIRProviderService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    #if os(macOS)
    @State private var healthAutoExportService = HealthAutoExportService()
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(whoopService)
            .environment(healthKitService)
            .environment(clinicalRecordService)
            .environment(fhirProviderService)
            #if os(macOS)
            .environment(healthAutoExportService)
            #endif
            .onOpenURL { url in
                if url.host == "whoop" {
                    Task { await whoopService.handleCallback(url: url) }
                }
                // FHIR callbacks are handled by ASWebAuthenticationSession directly
            }
        }
        .modelContainer(for: [
            Measurement.self,
            Medication.self,
            MedicationLog.self,
            Biomarker.self,
            Habit.self,
            HabitLog.self,
            Condition.self,
            DietPlan.self,
            MetricRange.self,
            VaultDocument.self,
            HealthMemory.self,
            Conversation.self
        ])
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Measurement") {
                    NotificationCenter.default.post(name: .addMeasurement, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChat, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Button("Vitals") {
                    NotificationCenter.default.post(name: .navigateTo, object: AppSection.vitals)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Correlations") {
                    NotificationCenter.default.post(name: .navigateTo, object: AppSection.correlations)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Biomarkers") {
                    NotificationCenter.default.post(name: .navigateTo, object: AppSection.biomarkers)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Medications") {
                    NotificationCenter.default.post(name: .navigateTo, object: AppSection.medications)
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Chat") {
                    NotificationCenter.default.post(name: .navigateTo, object: AppSection.chat)
                }
                .keyboardShortcut("5", modifiers: .command)
            }
        }
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let addMeasurement = Notification.Name("addMeasurement")
    static let newChat = Notification.Name("newChat")
    static let navigateTo = Notification.Name("navigateTo")
    static let switchToChat = Notification.Name("switchToChat")
}
