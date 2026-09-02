import Foundation
import SwiftData

/// Owns destructive data operations so Settings, backup restore, and tests share one definition.
enum DataLifecycleService {
    @MainActor
    static func clearDatabase(from context: ModelContext) throws {
        try context.delete(model: MedicationLog.self)
        try context.delete(model: HabitLog.self)
        try context.delete(model: AuraHealth.Measurement.self)
        try context.delete(model: Medication.self)
        try context.delete(model: Biomarker.self)
        try context.delete(model: Habit.self)
        try context.delete(model: Condition.self)
        try context.delete(model: DietPlan.self)
        try context.delete(model: MetricRange.self)
        try context.delete(model: Conversation.self)
        try context.delete(model: VaultDocument.self)
        try context.delete(model: HealthMemory.self)
        try context.delete(model: LabSession.self)
        try context.delete(model: SmartHabit.self)
        try context.delete(model: ProtocolMeta.self)
        try context.save()
    }

    @MainActor
    static func clearAllUserData(from context: ModelContext) throws {
        try clearDatabase(from: context)

        KeychainService.deleteVaultPassword()
        KeychainService.deleteValue(for: "claude-api-key")
        KeychainService.deleteValue(for: "anthropic-api-key")
        KeychainService.deleteValue(for: "openrouter-api-key")

        let defaults = UserDefaults.standard
        [
            "hasCompletedOnboarding",
            "weightUnit",
            "temperatureUnit",
            "claudeModel",
            "aiProvider",
            "aiModel",
            "ai-consent-anthropic",
            "ai-consent-openrouter",
            "hiddenMetrics",
            "dismissedInsights",
            "healthkit-authorized",
            "healthkit-last-sync",
            "clinical-records-authorized",
            "clinical-records-last-sync",
            "fhir-connected-providers",
        ].forEach(defaults.removeObject(forKey:))
    }
}
