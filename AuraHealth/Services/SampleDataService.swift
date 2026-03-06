import Foundation
import SwiftData

/// Generates realistic sample health data for QA/testing.
/// Temporary — remove before shipping.
struct SampleDataService {

    static func loadSampleData(into context: ModelContext) {
        // Guard against double-loading
        let existingMeasurements = (try? context.fetchCount(FetchDescriptor<Measurement>())) ?? 0
        if existingMeasurements > 0 { return }

        loadMeasurements(into: context)
        loadMedications(into: context)
        loadHabits(into: context)
        loadBiomarkers(into: context)
        loadConditions(into: context)
        loadDietPlans(into: context)
        loadMetricRanges(into: context)

        try? context.save()
    }

    static func clearAllData(from context: ModelContext) {
        try? context.delete(model: Measurement.self)
        try? context.delete(model: MedicationLog.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: HabitLog.self)
        try? context.delete(model: Habit.self)
        try? context.delete(model: Biomarker.self)
        try? context.delete(model: Condition.self)
        try? context.delete(model: DietPlan.self)
        try? context.delete(model: MetricRange.self)
        try? context.delete(model: Conversation.self)
        try? context.delete(model: HealthMemory.self)
        // Don't delete VaultDocuments — user may have real docs
        try? context.save()
    }

    // MARK: - Measurements (90 days of vitals)

    private static func loadMeasurements(into context: ModelContext) {
        let cal = Calendar.current

        for dayOffset in 0..<90 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let morning = cal.date(bySettingHour: 7, minute: Int.random(in: 0...59), second: 0, of: date)!
            let evening = cal.date(bySettingHour: 21, minute: Int.random(in: 0...59), second: 0, of: date)!

            // Weight — daily, slight downward trend with noise
            if dayOffset % 2 == 0 {
                let base = 82.0 - Double(dayOffset) * 0.02
                context.insert(Measurement(timestamp: morning, metricType: .weight, value: base + Double.random(in: -0.5...0.5), source: .manual))
            }

            // Blood Pressure — daily
            let sysBasis = 118.0 + Double.random(in: -8...8)
            let diaBasis = 76.0 + Double.random(in: -5...5)
            context.insert(Measurement(timestamp: morning, metricType: .bloodPressure, value: sysBasis, value2: diaBasis, source: .manual))

            // Heart Rate — twice daily
            context.insert(Measurement(timestamp: morning, metricType: .heartRate, value: Double(Int.random(in: 55...72)), source: .whoop))
            context.insert(Measurement(timestamp: evening, metricType: .heartRate, value: Double(Int.random(in: 62...85)), source: .whoop))

            // Sleep Score — daily
            context.insert(Measurement(timestamp: morning, metricType: .sleepScore, value: Double(Int.random(in: 65...98)), source: .whoop))

            // Sleep Duration — daily
            context.insert(Measurement(timestamp: morning, metricType: .sleepDuration, value: Double.random(in: 5.5...9.0), source: .whoop))

            // Steps — daily
            context.insert(Measurement(timestamp: evening, metricType: .steps, value: Double(Int.random(in: 4000...14000)), source: .appleHealth))

            // HRV — daily
            context.insert(Measurement(timestamp: morning, metricType: .hrv, value: Double(Int.random(in: 25...85)), source: .whoop))

            // Recovery — daily
            context.insert(Measurement(timestamp: morning, metricType: .recovery, value: Double(Int.random(in: 30...99)), source: .whoop))

            // Strain — daily
            context.insert(Measurement(timestamp: evening, metricType: .strain, value: Double.random(in: 4.0...18.0), source: .whoop))

            // SpO2 — daily
            context.insert(Measurement(timestamp: morning, metricType: .spo2, value: Double(Int.random(in: 95...99)), source: .whoop))

            // Skin Temp — daily
            context.insert(Measurement(timestamp: morning, metricType: .skinTemp, value: Double.random(in: 36.2...37.1), source: .whoop))

            // Calories — daily
            context.insert(Measurement(timestamp: evening, metricType: .calories, value: Double(Int.random(in: 1800...2800)), source: .appleHealth))
        }
    }

    // MARK: - Medications

    private static func loadMedications(into context: ModelContext) {
        let cal = Calendar.current
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: Date())!

        let meds: [(String, String, MedicationType, MedicationTiming, MedicationFrequency, String)] = [
            ("Vitamin D3", "5000 IU", .supplement, .amFasted, .daily, "Deficiency"),
            ("Omega-3 Fish Oil", "2000 mg", .supplement, .withFood, .daily, "Heart health"),
            ("Magnesium Glycinate", "400 mg", .supplement, .bedtime, .daily, "Sleep / recovery"),
            ("Metformin", "500 mg", .rx, .withFood, .twiceDaily, "Glucose management"),
            ("Ashwagandha", "600 mg", .supplement, .amFasted, .daily, "Stress / cortisol"),
            ("Ibuprofen", "200 mg", .otc, .anyTime, .asNeeded, "Pain relief"),
        ]

        for (name, dosage, type, timing, freq, condition) in meds {
            let med = Medication(
                name: name, dosage: dosage, frequency: freq,
                condition: condition, type: type, timing: timing,
                startDate: threeMonthsAgo
            )
            context.insert(med)

            // Generate logs for the last 90 days
            if freq != .asNeeded {
                for dayOffset in 0..<90 {
                    guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                    let taken = Double.random(in: 0...1) < 0.85 // 85% adherence
                    let log = MedicationLog(date: date, medication: med, taken: taken, dosage: dosage)
                    context.insert(log)
                }
            }
        }
    }

    // MARK: - Habits

    private static func loadHabits(into context: ModelContext) {
        let cal = Calendar.current

        let habits: [(String, HabitCategory, TrackingType, String, GridSection)] = [
            ("Meditation", .lifestyle, .boolean, "", .morning),
            ("Cold Shower", .therapy, .boolean, "", .morning),
            ("Read 30 min", .lifestyle, .boolean, "", .evening),
            ("Water Intake", .lifestyle, .quantity, "glasses", .morning),
            ("Stretching", .exercise, .boolean, "", .morning),
            ("No Alcohol", .diet, .boolean, "", .evening),
            ("Journaling", .lifestyle, .boolean, "", .evening),
            ("Walk 10k Steps", .exercise, .boolean, "", .afternoon),
        ]

        for (name, category, trackingType, unit, section) in habits {
            let habit = Habit(
                name: name, category: category, trackingType: trackingType,
                unit: unit, gridSection: section
            )
            context.insert(habit)

            // Generate logs for 90 days
            for dayOffset in 0..<90 {
                guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                let done = Double.random(in: 0...1) < 0.7 // 70% completion rate
                let quantity: Double? = trackingType == .quantity ? Double(Int.random(in: 4...10)) : nil
                let log = HabitLog(date: date, habit: habit, done: done, quantity: quantity, unit: unit)
                context.insert(log)
            }
        }
    }

    // MARK: - Biomarkers (3 test dates)

    private static func loadBiomarkers(into context: ModelContext) {
        let cal = Calendar.current
        let testDates = [
            cal.date(byAdding: .month, value: -6, to: Date())!,
            cal.date(byAdding: .month, value: -3, to: Date())!,
            Date()
        ]

        let markers: [(String, String, Double, Double, [Double])] = [
            // (name, unit, refMin, refMax, [values per test date])
            ("Total Cholesterol", "mg/dL", 125, 200, [215, 198, 188]),
            ("LDL Cholesterol", "mg/dL", 0, 100, [138, 118, 102]),
            ("HDL Cholesterol", "mg/dL", 40, 60, [42, 48, 55]),
            ("Triglycerides", "mg/dL", 0, 150, [165, 142, 128]),
            ("Fasting Glucose", "mg/dL", 70, 100, [108, 98, 92]),
            ("HbA1c", "%", 4.0, 5.7, [5.9, 5.6, 5.4]),
            ("TSH", "mIU/L", 0.4, 4.0, [2.1, 1.8, 2.0]),
            ("Free T4", "ng/dL", 0.8, 1.8, [1.2, 1.3, 1.2]),
            ("Vitamin D", "ng/mL", 30, 100, [22, 35, 48]),
            ("Ferritin", "ng/mL", 30, 400, [45, 68, 82]),
            ("CRP", "mg/L", 0, 3.0, [4.2, 2.8, 1.5]),
            ("ALT", "U/L", 7, 56, [32, 28, 25]),
            ("AST", "U/L", 10, 40, [28, 24, 22]),
            ("Creatinine", "mg/dL", 0.7, 1.3, [1.0, 0.9, 1.0]),
            ("eGFR", "mL/min", 90, 120, [95, 98, 102]),
            ("Testosterone", "ng/dL", 300, 1000, [380, 450, 520]),
        ]

        for (name, unit, refMin, refMax, values) in markers {
            for (i, testDate) in testDates.enumerated() {
                context.insert(Biomarker(
                    testDate: testDate, marker: name, value: values[i],
                    unit: unit, refMin: refMin, refMax: refMax,
                    lab: "Quest Diagnostics"
                ))
            }
        }
    }

    // MARK: - Conditions

    private static func loadConditions(into context: ModelContext) {
        let cal = Calendar.current
        context.insert(Condition(name: "Pre-diabetes", status: .managed,
            diagnosedDate: cal.date(byAdding: .year, value: -1, to: Date()), notes: "Managing with Metformin + diet"))
        context.insert(Condition(name: "Vitamin D Deficiency", status: .managed,
            diagnosedDate: cal.date(byAdding: .month, value: -6, to: Date()), notes: "Supplementing 5000 IU daily"))
        context.insert(Condition(name: "Mild Hypercholesterolemia", status: .active,
            diagnosedDate: cal.date(byAdding: .month, value: -6, to: Date()), notes: "Diet-controlled, monitoring"))
    }

    // MARK: - Diet Plans

    private static func loadDietPlans(into context: ModelContext) {
        let cal = Calendar.current
        context.insert(DietPlan(
            name: "Mediterranean Diet",
            dietType: "Mediterranean",
            startDate: cal.date(byAdding: .month, value: -2, to: Date()),
            allowedFoods: ["Olive oil", "Fish", "Vegetables", "Whole grains", "Nuts", "Legumes", "Fruits"],
            avoidFoods: ["Processed foods", "Refined sugar", "Red meat", "Butter"],
            foodCategories: ["Proteins", "Vegetables", "Healthy Fats", "Whole Grains"],
            notes: "Focus on anti-inflammatory foods"
        ))
    }

    // MARK: - Metric Ranges (personal targets)

    private static func loadMetricRanges(into context: ModelContext) {
        context.insert(MetricRange(metricType: .weight, low: 78, high: 83))
        context.insert(MetricRange(metricType: .heartRate, low: 55, high: 75))
        context.insert(MetricRange(metricType: .sleepScore, low: 80, high: 100))
        context.insert(MetricRange(metricType: .hrv, low: 40, high: 90))
        context.insert(MetricRange(metricType: .recovery, low: 60, high: 100))
        context.insert(MetricRange(metricType: .steps, low: 8000, high: 15000))
    }
}
