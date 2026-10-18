import Foundation
import SwiftData

/// Records that people commonly keep an eye on for a condition. Educational
/// only: the link sheet lists them under "Often tracked with" and the user
/// decides what to link. Nothing is linked automatically.
enum ConditionSuggestions {
    struct Suggestion {
        let markers: [String]
        let metrics: [MetricType]
    }

    /// Keyword in the condition name → suggestion. Checked in order; the first match wins.
    private static let table: [(keywords: [String], suggestion: Suggestion)] = [
        (["diabet", "insulin resistance", "metabolic syndrome"],
         Suggestion(markers: ["HbA1c", "Fasting Glucose", "Triglycerides"], metrics: [.weight])),
        (["cholesterol", "hyperlipid", "dyslipid"],
         Suggestion(markers: ["LDL Cholesterol", "HDL Cholesterol", "Total Cholesterol", "Triglycerides"], metrics: [])),
        (["hypertension", "blood pressure"],
         Suggestion(markers: [], metrics: [.bloodPressure, .heartRate])),
        (["heart", "atrial", "artery"],
         Suggestion(markers: ["LDL Cholesterol", "Apolipoprotein B"], metrics: [.bloodPressure, .heartRate, .hrv])),
        (["thyroid", "hashimoto"],
         Suggestion(markers: ["TSH", "Free T4", "Free T3"], metrics: [.heartRate, .weight])),
        (["vitamin d"],
         Suggestion(markers: ["Vitamin D"], metrics: [])),
        (["anemia", "iron"],
         Suggestion(markers: ["Hemoglobin", "Ferritin"], metrics: [])),
        (["kidney"],
         Suggestion(markers: ["Creatinine", "eGFR"], metrics: [.bloodPressure])),
        (["fatty liver", "liver"],
         Suggestion(markers: ["ALT", "AST"], metrics: [.weight])),
        (["gout"],
         Suggestion(markers: ["Uric Acid"], metrics: [])),
        (["sleep apnea"],
         Suggestion(markers: [], metrics: [.spo2, .sleepDuration])),
        (["insomnia"],
         Suggestion(markers: [], metrics: [.sleepDuration, .sleepScore])),
        (["obesity"],
         Suggestion(markers: ["HbA1c"], metrics: [.weight, .steps])),
        (["rheumatoid", "lupus", "psoriasis", "crohn", "colitis"],
         Suggestion(markers: ["hs-CRP"], metrics: [])),
    ]

    static func suggestion(for conditionName: String) -> Suggestion? {
        let name = conditionName.lowercased()
        return table.first { entry in entry.keywords.contains { name.contains($0) } }?.suggestion
    }

    /// True when two marker names mean the same test ("Fasting Glucose" and "Glucose").
    static func sameMarker(_ a: String, _ b: String) -> Bool {
        BiomarkerReference.canonicalName(for: a).lowercased() == BiomarkerReference.canonicalName(for: b).lowercased()
    }
}

extension Condition {
    var linkedMedications: [Medication] {
        (medications ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var linkedHabits: [Habit] {
        (habits ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var linkedMetrics: [MetricType] {
        trackedMetrics.compactMap(MetricType.init(rawValue:))
    }

    var hasLinks: Bool {
        !trackedMarkers.isEmpty || !trackedMetrics.isEmpty || !(medications ?? []).isEmpty || !(habits ?? []).isEmpty
    }

    /// "2 labs · 1 vital · 1 med · 1 habit", or nil when nothing is linked.
    var linkSummary: String? {
        func count(_ n: Int, _ one: String, _ many: String) -> String? {
            n == 0 ? nil : "\(n) \(n == 1 ? one : many)"
        }
        let parts = [
            count(trackedMarkers.count, "lab", "labs"),
            count(trackedMetrics.count, "vital", "vitals"),
            count((medications ?? []).count, "med", "meds"),
            count((habits ?? []).count, "habit", "habits"),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - One-time link pass

enum ConditionLinkMigration {
    private static let doneKey = "conditionLinksMigrated"

    /// Once, after condition links arrive: link each med whose "Taken for" text
    /// is exactly a condition's name, ignoring case. Everything else is linked by hand.
    @MainActor
    static func linkMedicationsByName(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        let conditions = (try? context.fetch(FetchDescriptor<Condition>())) ?? []
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        for med in meds where !med.condition.isEmpty {
            let purpose = med.condition.trimmingCharacters(in: .whitespaces)
            for condition in conditions where condition.name.caseInsensitiveCompare(purpose) == .orderedSame {
                if !(med.conditions ?? []).contains(where: { $0.id == condition.id }) {
                    med.conditions = (med.conditions ?? []) + [condition]
                }
            }
        }
        try? context.save()
        defaults.set(true, forKey: doneKey)
    }
}
