import SwiftUI
import SwiftData
import os

@main
struct AuraHealthApp: App {
    @State private var healthKitService = HealthKitService()
    @State private var dailyProtocolService = DailyProtocolService()
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
            .environment(healthKitService)
            .environment(dailyProtocolService)
            #if os(macOS)
            .environment(healthAutoExportService)
            #endif
        }
        .modelContainer(auraContainer)
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

// MARK: - Model Container

private let auraContainer: ModelContainer = {
    let schema = Schema([
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
        Conversation.self,
        SmartHabit.self,
        ProtocolMeta.self,
        LabSession.self
    ])

    let config = ModelConfiguration("AuraHealth", schema: schema, cloudKitDatabase: .automatic)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        // Existing local store is incompatible with CloudKit — delete it and create fresh
        // This happens once when migrating from local-only to CloudKit sync
        let logger = os.Logger(subsystem: "com.santiagoalonso.aurahealth", category: "Migration")
        logger.warning("CloudKit container failed, migrating: \(error.localizedDescription)")

        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeFiles = ["AuraHealth.store", "AuraHealth.store-shm", "AuraHealth.store-wal"]
        for file in storeFiles {
            let url = appSupport.appendingPathComponent(file)
            try? fileManager.removeItem(at: url)
        }
        // Also check default SwiftData location
        let defaultFiles = ["default.store", "default.store-shm", "default.store-wal"]
        for file in defaultFiles {
            let url = appSupport.appendingPathComponent(file)
            try? fileManager.removeItem(at: url)
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer after migration: \(error)")
        }
    }
}()

// MARK: - Notification Names

extension Notification.Name {
    static let addMeasurement = Notification.Name("addMeasurement")
    static let newChat = Notification.Name("newChat")
    static let navigateTo = Notification.Name("navigateTo")
    static let switchToChat = Notification.Name("switchToChat")
    static let openMetricDetail = Notification.Name("openMetricDetail")
}
