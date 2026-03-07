import Foundation
import SwiftData

/// Seeds biomarker data extracted from lab reports into SwiftData
enum LabDataSeeder {

    struct LabEntry {
        let marker: String
        let value: Double
        let unit: String
        let refMin: Double?
        let refMax: Double?
        let lab: String
    }

    // MARK: - Public

    static func importAllLabs(into context: ModelContext) {
        let allLabs: [(Date, [LabEntry])] = [
            (date(2025, 12, 8), questDec2025),
            (date(2026, 1, 19), labcorpJan2026),
            (date(2026, 3, 5), maximusMar2026),
        ]

        var inserted = 0
        for (testDate, entries) in allLabs {
            for entry in entries {
                if insertIfNew(context: context, testDate: testDate, entry: entry) {
                    inserted += 1
                }
            }
        }

        try? context.save()
        print("[LabDataSeeder] Inserted \(inserted) biomarkers across \(allLabs.count) labs")
    }

    // MARK: - Dedup

    private static func insertIfNew(context: ModelContext, testDate: Date, entry: LabEntry) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: testDate)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<Biomarker>(
            predicate: #Predicate { $0.testDate >= start && $0.testDate < end }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let alreadyExists = existing.contains { $0.marker == entry.marker }

        if !alreadyExists {
            context.insert(Biomarker(
                testDate: testDate,
                marker: entry.marker,
                value: entry.value,
                unit: entry.unit,
                refMin: entry.refMin,
                refMax: entry.refMax,
                lab: entry.lab
            ))
            return true
        }
        return false
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Quest Diagnostics — Dec 8, 2025

    private static let questDec2025: [LabEntry] = [
        // Heart / Lipids
        LabEntry(marker: "Total Cholesterol", value: 166, unit: "mg/dL", refMin: 0, refMax: 200, lab: "Quest"),
        LabEntry(marker: "Triglycerides", value: 86, unit: "mg/dL", refMin: 0, refMax: 150, lab: "Quest"),
        LabEntry(marker: "LDL Cholesterol", value: 99, unit: "mg/dL", refMin: 0, refMax: 100, lab: "Quest"),
        LabEntry(marker: "HDL Cholesterol", value: 49, unit: "mg/dL", refMin: 40, refMax: 100, lab: "Quest"),
        LabEntry(marker: "Non-HDL Cholesterol", value: 117, unit: "mg/dL", refMin: 0, refMax: 130, lab: "Quest"),
        LabEntry(marker: "Apolipoprotein B", value: 85, unit: "mg/dL", refMin: 0, refMax: 90, lab: "Quest"),

        // Inflammation
        LabEntry(marker: "hs-CRP", value: 0.2, unit: "mg/L", refMin: 0, refMax: 1.0, lab: "Quest"),

        // Metabolic
        LabEntry(marker: "HbA1c", value: 4.8, unit: "%", refMin: 0, refMax: 5.7, lab: "Quest"),
        LabEntry(marker: "Glucose", value: 96, unit: "mg/dL", refMin: 65, refMax: 99, lab: "Quest"),
        LabEntry(marker: "Insulin", value: 10.6, unit: "uIU/mL", refMin: 0, refMax: 18.4, lab: "Quest"),

        // Kidney
        LabEntry(marker: "Creatinine", value: 1.16, unit: "mg/dL", refMin: 0.60, refMax: 1.26, lab: "Quest"),
        LabEntry(marker: "eGFR", value: 83, unit: "mL/min/1.73m2", refMin: 60, refMax: 120, lab: "Quest"),
        LabEntry(marker: "BUN", value: 15, unit: "mg/dL", refMin: 7, refMax: 25, lab: "Quest"),

        // Liver
        LabEntry(marker: "Bilirubin, Total", value: 0.6, unit: "mg/dL", refMin: 0.2, refMax: 1.2, lab: "Quest"),
        LabEntry(marker: "AST", value: 20, unit: "U/L", refMin: 10, refMax: 40, lab: "Quest"),
        LabEntry(marker: "ALT", value: 18, unit: "U/L", refMin: 9, refMax: 46, lab: "Quest"),
        LabEntry(marker: "Alkaline Phosphatase", value: 50, unit: "U/L", refMin: 36, refMax: 130, lab: "Quest"),
        LabEntry(marker: "Albumin", value: 4.8, unit: "g/dL", refMin: 3.6, refMax: 5.1, lab: "Quest"),
        LabEntry(marker: "Protein, Total", value: 7.1, unit: "g/dL", refMin: 6.1, refMax: 8.1, lab: "Quest"),
        LabEntry(marker: "Globulin", value: 2.3, unit: "g/dL", refMin: 1.9, refMax: 3.7, lab: "Quest"),

        // Thyroid
        LabEntry(marker: "TSH", value: 5.01, unit: "mIU/L", refMin: 0.40, refMax: 4.50, lab: "Quest"),
        LabEntry(marker: "Free T4", value: 1.6, unit: "ng/dL", refMin: 0.8, refMax: 1.8, lab: "Quest"),
        LabEntry(marker: "Free T3", value: 3.8, unit: "pg/mL", refMin: 2.3, refMax: 4.2, lab: "Quest"),

        // Blood / CBC
        LabEntry(marker: "WBC", value: 8.5, unit: "x10E3/uL", refMin: 3.8, refMax: 10.8, lab: "Quest"),
        LabEntry(marker: "RBC", value: 5.21, unit: "x10E6/uL", refMin: 4.20, refMax: 5.80, lab: "Quest"),
        LabEntry(marker: "Hemoglobin", value: 15.7, unit: "g/dL", refMin: 13.2, refMax: 17.1, lab: "Quest"),
        LabEntry(marker: "Hematocrit", value: 48.7, unit: "%", refMin: 39.4, refMax: 51.1, lab: "Quest"),
        LabEntry(marker: "MCV", value: 93.5, unit: "fL", refMin: 81.4, refMax: 101.7, lab: "Quest"),
        LabEntry(marker: "MCH", value: 30.1, unit: "pg", refMin: 27.0, refMax: 33.0, lab: "Quest"),
        LabEntry(marker: "MCHC", value: 32.2, unit: "g/dL", refMin: 31.6, refMax: 35.4, lab: "Quest"),
        LabEntry(marker: "RDW", value: 13.9, unit: "%", refMin: 11.0, refMax: 15.0, lab: "Quest"),
        LabEntry(marker: "Platelets", value: 294, unit: "x10E3/uL", refMin: 140, refMax: 400, lab: "Quest"),

        // Electrolytes
        LabEntry(marker: "Sodium", value: 134, unit: "mmol/L", refMin: 135, refMax: 146, lab: "Quest"),
        LabEntry(marker: "Potassium", value: 4.2, unit: "mmol/L", refMin: 3.5, refMax: 5.3, lab: "Quest"),
        LabEntry(marker: "Chloride", value: 99, unit: "mmol/L", refMin: 98, refMax: 110, lab: "Quest"),
        LabEntry(marker: "Carbon Dioxide", value: 28, unit: "mmol/L", refMin: 20, refMax: 32, lab: "Quest"),
        LabEntry(marker: "Calcium", value: 9.0, unit: "mg/dL", refMin: 8.6, refMax: 10.3, lab: "Quest"),

        // Vitamins
        LabEntry(marker: "Vitamin D", value: 65, unit: "ng/mL", refMin: 30, refMax: 100, lab: "Quest"),
        LabEntry(marker: "Folate", value: 16.5, unit: "ng/mL", refMin: 5.4, refMax: 40, lab: "Quest"),
        LabEntry(marker: "Vitamin B12", value: 586, unit: "pg/mL", refMin: 200, refMax: 1100, lab: "Quest"),

        // Hormones
        LabEntry(marker: "Testosterone, Total", value: 1024, unit: "ng/dL", refMin: 250, refMax: 1100, lab: "Quest"),
        LabEntry(marker: "Ferritin", value: 94, unit: "ng/mL", refMin: 38, refMax: 380, lab: "Quest"),
    ]

    // MARK: - LabCorp — Jan 19, 2026

    private static let labcorpJan2026: [LabEntry] = [
        // CBC
        LabEntry(marker: "WBC", value: 8.2, unit: "x10E3/uL", refMin: 3.4, refMax: 10.8, lab: "LabCorp"),
        LabEntry(marker: "RBC", value: 5.72, unit: "x10E6/uL", refMin: 4.14, refMax: 5.80, lab: "LabCorp"),
        LabEntry(marker: "Hemoglobin", value: 17.2, unit: "g/dL", refMin: 13.0, refMax: 17.7, lab: "LabCorp"),
        LabEntry(marker: "Hematocrit", value: 51.5, unit: "%", refMin: 37.5, refMax: 51.0, lab: "LabCorp"),
        LabEntry(marker: "MCV", value: 90, unit: "fL", refMin: 79, refMax: 97, lab: "LabCorp"),
        LabEntry(marker: "MCH", value: 30.1, unit: "pg", refMin: 26.6, refMax: 33.0, lab: "LabCorp"),
        LabEntry(marker: "MCHC", value: 33.4, unit: "g/dL", refMin: 31.5, refMax: 35.7, lab: "LabCorp"),
        LabEntry(marker: "RDW", value: 13.8, unit: "%", refMin: 11.6, refMax: 15.4, lab: "LabCorp"),
        LabEntry(marker: "Platelets", value: 291, unit: "x10E3/uL", refMin: 150, refMax: 450, lab: "LabCorp"),

        // CMP
        LabEntry(marker: "Glucose", value: 81, unit: "mg/dL", refMin: 70, refMax: 99, lab: "LabCorp"),
        LabEntry(marker: "BUN", value: 11, unit: "mg/dL", refMin: 6, refMax: 20, lab: "LabCorp"),
        LabEntry(marker: "Creatinine", value: 0.93, unit: "mg/dL", refMin: 0.76, refMax: 1.27, lab: "LabCorp"),
        LabEntry(marker: "eGFR", value: 108, unit: "mL/min/1.73m2", refMin: 60, refMax: 120, lab: "LabCorp"),
        LabEntry(marker: "Sodium", value: 136, unit: "mmol/L", refMin: 134, refMax: 144, lab: "LabCorp"),
        LabEntry(marker: "Potassium", value: 4.8, unit: "mmol/L", refMin: 3.5, refMax: 5.2, lab: "LabCorp"),
        LabEntry(marker: "Chloride", value: 99, unit: "mmol/L", refMin: 96, refMax: 106, lab: "LabCorp"),
        LabEntry(marker: "Carbon Dioxide", value: 19, unit: "mmol/L", refMin: 20, refMax: 29, lab: "LabCorp"),
        LabEntry(marker: "Calcium", value: 9.4, unit: "mg/dL", refMin: 8.7, refMax: 10.2, lab: "LabCorp"),
        LabEntry(marker: "Protein, Total", value: 7.9, unit: "g/dL", refMin: 6.0, refMax: 8.5, lab: "LabCorp"),
        LabEntry(marker: "Albumin", value: 5.3, unit: "g/dL", refMin: 4.1, refMax: 5.1, lab: "LabCorp"),
        LabEntry(marker: "Globulin", value: 2.6, unit: "g/dL", refMin: 1.5, refMax: 4.5, lab: "LabCorp"),
        LabEntry(marker: "Bilirubin, Total", value: 0.6, unit: "mg/dL", refMin: 0, refMax: 1.2, lab: "LabCorp"),
        LabEntry(marker: "Alkaline Phosphatase", value: 54, unit: "IU/L", refMin: 47, refMax: 123, lab: "LabCorp"),
        LabEntry(marker: "AST", value: 31, unit: "IU/L", refMin: 0, refMax: 40, lab: "LabCorp"),
        LabEntry(marker: "ALT", value: 24, unit: "IU/L", refMin: 0, refMax: 44, lab: "LabCorp"),

        // Lipids
        LabEntry(marker: "Total Cholesterol", value: 223, unit: "mg/dL", refMin: 100, refMax: 199, lab: "LabCorp"),
        LabEntry(marker: "Triglycerides", value: 54, unit: "mg/dL", refMin: 0, refMax: 149, lab: "LabCorp"),
        LabEntry(marker: "HDL Cholesterol", value: 57, unit: "mg/dL", refMin: 40, refMax: 100, lab: "LabCorp"),
        LabEntry(marker: "LDL Cholesterol", value: 157, unit: "mg/dL", refMin: 0, refMax: 99, lab: "LabCorp"),

        // Thyroid
        LabEntry(marker: "TSH", value: 3.53, unit: "uIU/mL", refMin: 0.45, refMax: 4.50, lab: "LabCorp"),
        LabEntry(marker: "T4", value: 7.4, unit: "ug/dL", refMin: 4.5, refMax: 12.0, lab: "LabCorp"),

        // Other
        LabEntry(marker: "Cystatin C", value: 0.64, unit: "mg/L", refMin: 0.60, refMax: 1.00, lab: "LabCorp"),
    ]

    // MARK: - Maximus / CRL King — Mar 5, 2026

    private static let maximusMar2026: [LabEntry] = [
        // Hormones
        LabEntry(marker: "Testosterone, Total", value: 901, unit: "ng/dL", refMin: 193, refMax: 836, lab: "Maximus"),
        LabEntry(marker: "Free Testosterone", value: 214, unit: "pg/mL", refMin: 0.1, refMax: 190, lab: "Maximus"),
        LabEntry(marker: "LH", value: 7.8, unit: "IU/L", refMin: 1.7, refMax: 8.6, lab: "Maximus"),
        LabEntry(marker: "Estradiol", value: 36.3, unit: "pg/mL", refMin: 11.3, refMax: 43.0, lab: "Maximus"),
        LabEntry(marker: "SHBG", value: 32.9, unit: "nmol/L", refMin: 16.5, refMax: 76.0, lab: "Maximus"),
        LabEntry(marker: "PSA", value: 0.6, unit: "ng/mL", refMin: 0, refMax: 4.0, lab: "Maximus"),

        // Blood
        LabEntry(marker: "Hemoglobin", value: 16.8, unit: "g/dL", refMin: 12.9, refMax: 17.7, lab: "Maximus"),
        LabEntry(marker: "Hematocrit", value: 50.0, unit: "%", refMin: 41.0, refMax: 52.0, lab: "Maximus"),
    ]
}
