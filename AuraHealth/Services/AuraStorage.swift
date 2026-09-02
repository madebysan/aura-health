import Foundation
import SwiftData
import os

struct AuraStorageState {
    let container: ModelContainer
    let startupError: String?
}

enum AuraStorage {
    static let schema = Schema([
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
        // Kept temporarily so existing TestFlight stores can migrate without data loss.
        SmartHabit.self,
        ProtocolMeta.self,
        LabSession.self,
    ])

    static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "AuraHealth",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeAppState() -> AuraStorageState {
        do {
            return AuraStorageState(container: try makeContainer(), startupError: nil)
        } catch {
            let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "Storage")
            logger.error("Local store failed to open: \(error.localizedDescription, privacy: .private)")

            do {
                let fallback = try makeContainer(isStoredInMemoryOnly: true)
                return AuraStorageState(
                    container: fallback,
                    startupError: "Aura could not safely open your local data. Your existing records were not deleted. Close the app and contact support before importing, clearing, or adding data."
                )
            } catch {
                fatalError("Aura could not create its recovery container.")
            }
        }
    }
}
