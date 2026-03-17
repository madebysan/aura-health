import Foundation
import SwiftUI

// MARK: - Metric Types

enum MetricType: String, Codable, CaseIterable, Identifiable {
    case weight
    case bloodPressure
    case heartRate
    case sleepScore
    case sleepDuration
    case steps
    case activeMinutes
    case hrv
    case recovery
    case strain
    case spo2
    case skinTemp
    case calories

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weight: "Weight"
        case .bloodPressure: "Blood Pressure"
        case .heartRate: "Heart Rate"
        case .sleepScore: "Sleep Score"
        case .sleepDuration: "Sleep Duration"
        case .steps: "Steps"
        case .activeMinutes: "Active Minutes"
        case .hrv: "HRV"
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .spo2: "SpO2"
        case .skinTemp: "Skin Temp"
        case .calories: "Calories"
        }
    }

    var unit: String {
        switch self {
        case .weight: "kg"
        case .bloodPressure: "mmHg"
        case .heartRate: "bpm"
        case .sleepScore: "%"
        case .sleepDuration: "hrs"
        case .steps: "steps"
        case .activeMinutes: "min"
        case .hrv: "ms"
        case .recovery: "%"
        case .strain: ""
        case .spo2: "%"
        case .skinTemp: "C"
        case .calories: "kcal"
        }
    }

    var iconName: String {
        switch self {
        case .weight: "scalemass"
        case .bloodPressure: "heart.fill"
        case .heartRate: "waveform.path.ecg"
        case .sleepScore: "moon.fill"
        case .sleepDuration: "bed.double.fill"
        case .steps: "figure.walk"
        case .activeMinutes: "flame.fill"
        case .hrv: "waveform.path.ecg.rectangle"
        case .recovery: "arrow.2.circlepath"
        case .strain: "bolt.heart.fill"
        case .spo2: "lungs.fill"
        case .skinTemp: "thermometer.medium"
        case .calories: "flame"
        }
    }

    /// Whether this metric has a secondary value (e.g., diastolic for BP)
    var hasDualValue: Bool {
        self == .bloodPressure
    }

    /// Default healthy range for the composite score
    var defaultRange: (low: Double, high: Double) {
        switch self {
        case .weight: (50, 100)
        case .bloodPressure: (90, 120) // systolic
        case .heartRate: (50, 100)
        case .sleepScore: (70, 100)
        case .sleepDuration: (7, 9)
        case .steps: (7000, 15000)
        case .activeMinutes: (30, 120)
        case .hrv: (20, 100)
        case .recovery: (50, 100)
        case .strain: (8, 18)
        case .spo2: (95, 100)
        case .skinTemp: (36.1, 37.2)
        case .calories: (1800, 3000)
        }
    }
    /// Educational context for the metric detail view
    var context: MetricContext {
        switch self {
        case .weight:
            MetricContext(
                description: "Body weight is a basic but important health indicator. It reflects overall energy balance and can signal changes in muscle mass, hydration, or fat stores.",
                whyItMatters: "Tracking weight trends over weeks and months is more useful than any single reading. Sudden changes may indicate fluid shifts, dietary changes, or underlying health issues.",
                rangeExplanation: "The reference range of 50–100 kg is a general guideline for adults. Your ideal weight depends on height, body composition, age, and sex. BMI is a rough proxy — talk to your doctor about what's right for you."
            )
        case .bloodPressure:
            MetricContext(
                description: "Blood pressure measures the force of blood against artery walls. The top number (systolic) is pressure during heartbeats; the bottom (diastolic) is pressure between beats.",
                whyItMatters: "High blood pressure is a leading risk factor for heart disease, stroke, and kidney damage. It's often called the 'silent killer' because it rarely has symptoms until damage is done.",
                rangeExplanation: "Normal is below 120/80 mmHg. Elevated is 120–129 systolic. Stage 1 hypertension is 130–139/80–89. Stage 2 is 140+/90+. Consistently elevated readings warrant a conversation with your doctor."
            )
        case .heartRate:
            MetricContext(
                description: "Resting heart rate is how many times your heart beats per minute while at rest. It's a simple measure of cardiovascular fitness and autonomic nervous system health.",
                whyItMatters: "A lower resting heart rate generally indicates better cardiovascular fitness. Athletes often have resting rates in the 40–60 range. Sustained elevated rates may signal stress, dehydration, or heart conditions.",
                rangeExplanation: "50–100 bpm is the normal adult range. Below 60 is bradycardia (often fine if you're fit), above 100 is tachycardia. Your personal baseline matters more than population averages."
            )
        case .sleepScore:
            MetricContext(
                description: "Sleep score is a composite rating of your sleep quality, combining duration, efficiency, restfulness, and sleep stage balance into a single number.",
                whyItMatters: "Sleep quality affects everything — immune function, cognitive performance, mood, hormone regulation, and recovery. A consistently low score suggests your sleep needs attention.",
                rangeExplanation: "70–100 is considered good to excellent. Below 70 suggests poor sleep quality. Focus on consistency — going to bed and waking at the same time matters as much as total hours."
            )
        case .sleepDuration:
            MetricContext(
                description: "Total time spent asleep, including light, deep, and REM stages. This excludes time awake in bed.",
                whyItMatters: "Chronic sleep deprivation increases risk for obesity, diabetes, cardiovascular disease, and cognitive decline. Most adults need 7–9 hours, though individual needs vary.",
                rangeExplanation: "7–9 hours is recommended for most adults. Some people function well on 7, others need closer to 9. Less than 6 hours consistently is associated with significant health risks."
            )
        case .steps:
            MetricContext(
                description: "Daily step count is a simple proxy for overall physical activity and movement throughout the day.",
                whyItMatters: "Research shows mortality risk drops significantly going from sedentary to ~7,000–8,000 steps/day. Benefits continue up to ~12,000 steps but with diminishing returns. Any movement helps.",
                rangeExplanation: "7,000–15,000 steps is a healthy range. The 10,000 step goal is a useful target, not a medical threshold. What matters most is being consistently active relative to your baseline."
            )
        case .activeMinutes:
            MetricContext(
                description: "Minutes spent in moderate to vigorous physical activity, like brisk walking, running, or strength training.",
                whyItMatters: "The WHO recommends 150–300 minutes of moderate activity per week (about 22–43 min/day). Regular activity reduces risk of heart disease, diabetes, cancer, and depression.",
                rangeExplanation: "30–120 minutes daily is a healthy range. Even 15 minutes of brisk walking provides benefits. The key is consistency — daily movement beats occasional intense workouts."
            )
        case .hrv:
            MetricContext(
                description: "Heart rate variability measures the variation in time between consecutive heartbeats. It's controlled by the autonomic nervous system and reflects your body's ability to adapt to stress.",
                whyItMatters: "Higher HRV generally indicates better recovery, fitness, and stress resilience. Low HRV can signal overtraining, illness, poor sleep, or chronic stress. It's one of the best objective markers of overall readiness.",
                rangeExplanation: "20–100 ms is a typical range, but HRV is highly individual — it varies by age, fitness, and genetics. Your personal trend matters far more than comparing to others. Track it at the same time daily (morning is best)."
            )
        case .recovery:
            MetricContext(
                description: "Recovery score estimates how prepared your body is for strain based on sleep performance, HRV, and resting heart rate.",
                whyItMatters: "Training when recovery is low increases injury risk and can lead to overtraining. High recovery days are ideal for intense workouts. Low recovery days benefit from rest or light activity.",
                rangeExplanation: "50–100% is the target zone. Green (67–100%) means you're ready for strain. Yellow (34–66%) suggests moderation. Red (0–33%) means prioritize rest and recovery."
            )
        case .strain:
            MetricContext(
                description: "Strain is a measure of cardiovascular load throughout the day, based on heart rate data. It quantifies how much stress your body experienced from physical activity.",
                whyItMatters: "Balancing strain with recovery is key to improving fitness without overtraining. Consistently high strain without adequate recovery leads to diminishing returns and increased injury risk.",
                rangeExplanation: "8–18 is a moderate to high activity range. Light days score 0–8, intense training days 14–21. The goal is matching strain to your recovery level, not maximizing it every day."
            )
        case .spo2:
            MetricContext(
                description: "Blood oxygen saturation (SpO2) measures the percentage of hemoglobin in your blood that is carrying oxygen. It's typically measured by a pulse oximeter or wearable sensor.",
                whyItMatters: "Healthy lungs maintain SpO2 above 95%. Drops below 90% are clinically concerning and may indicate respiratory issues. During sleep, mild dips are normal but sustained drops may signal sleep apnea.",
                rangeExplanation: "95–100% is normal. 90–94% warrants medical attention. Below 90% is hypoxemia and needs immediate evaluation. High-altitude environments can naturally lower readings."
            )
        case .skinTemp:
            MetricContext(
                description: "Skin temperature reflects your body's thermoregulation. Wearables measure it continuously, usually at the wrist, and track deviations from your personal baseline.",
                whyItMatters: "Temperature variations can be early indicators of illness, hormonal changes, or circadian rhythm shifts. A sustained increase above your baseline may suggest your immune system is fighting something.",
                rangeExplanation: "36.1–37.2°C (97.0–99.0°F) is the normal range for skin temperature. Core body temperature is slightly higher. Individual baselines vary — track your personal pattern rather than absolute values."
            )
        case .calories:
            MetricContext(
                description: "Active calories burned through physical movement and exercise, as estimated by your device using heart rate, motion, and body metrics.",
                whyItMatters: "Tracking energy expenditure helps with weight management and ensures you're meeting activity goals. It's an imperfect estimate — wearables can be off by 15–30% — but trends over time are reliable.",
                rangeExplanation: "1,800–3,000 kcal is a typical daily active burn range for adults. Your actual needs depend on age, weight, activity level, and metabolic rate. Use this as a trend indicator, not a precise measurement."
            )
        }
    }
}

/// Educational context shown in the metric detail view
struct MetricContext {
    let description: String
    let whyItMatters: String
    let rangeExplanation: String
}

// MARK: - Measurement Source

enum MeasurementSource: String, Codable, CaseIterable {
    case manual
    case csv
    case whoop
    case appleHealth
    case clinicalRecord

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .csv: "CSV Import"
        case .whoop: "WHOOP"
        case .appleHealth: "Apple Health"
        case .clinicalRecord: "Clinical Record"
        }
    }
}

// MARK: - Medication

enum MedicationType: String, Codable, CaseIterable {
    case rx
    case supplement
    case otc

    var displayName: String {
        switch self {
        case .rx: "Prescription"
        case .supplement: "Supplement"
        case .otc: "OTC"
        }
    }
}

enum MedicationTiming: String, Codable, CaseIterable {
    case amFasted
    case withFood
    case bedtime
    case anyTime

    var displayName: String {
        switch self {
        case .amFasted: "AM Fasted"
        case .withFood: "With Food"
        case .bedtime: "Bedtime"
        case .anyTime: "Any Time"
        }
    }
}

enum MedicationFrequency: String, Codable, CaseIterable {
    case daily
    case twiceDaily
    case threeTimesDaily
    case weekly
    case asNeeded

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .twiceDaily: "Twice Daily"
        case .threeTimesDaily: "3x Daily"
        case .weekly: "Weekly"
        case .asNeeded: "As Needed"
        }
    }
}

// MARK: - Habits

enum HabitCategory: String, Codable, CaseIterable {
    case lifestyle
    case therapy
    case diet
    case exercise

    var displayName: String {
        switch self {
        case .lifestyle: "Lifestyle"
        case .therapy: "Therapy"
        case .diet: "Diet"
        case .exercise: "Exercise"
        }
    }
}

enum TrackingType: String, Codable {
    case boolean
    case quantity
}

// MARK: - Conditions

/// Common health conditions for autocomplete suggestions
enum CommonCondition: String, CaseIterable {
    // Metabolic & Endocrine
    case type1Diabetes = "Type 1 Diabetes"
    case type2Diabetes = "Type 2 Diabetes"
    case hypothyroidism = "Hypothyroidism"
    case hyperthyroidism = "Hyperthyroidism"
    case metabolicSyndrome = "Metabolic Syndrome"
    case pcos = "Polycystic Ovary Syndrome (PCOS)"
    case obesity = "Obesity"
    case insulinResistance = "Insulin Resistance"

    // Cardiovascular
    case hypertension = "Hypertension"
    case highCholesterol = "High Cholesterol"
    case heartDisease = "Heart Disease"
    case atrialFibrillation = "Atrial Fibrillation"
    case heartFailure = "Heart Failure"
    case peripheralArteryDisease = "Peripheral Artery Disease"

    // Respiratory
    case asthma = "Asthma"
    case copd = "COPD"
    case sleepApnea = "Sleep Apnea"
    case allergicRhinitis = "Allergic Rhinitis"
    case chronicSinusitis = "Chronic Sinusitis"

    // Mental Health
    case anxiety = "Anxiety"
    case depression = "Depression"
    case bipolarDisorder = "Bipolar Disorder"
    case adhd = "ADHD"
    case ptsd = "PTSD"
    case ocd = "OCD"
    case insomnia = "Insomnia"

    // Musculoskeletal
    case osteoarthritis = "Osteoarthritis"
    case rheumatoidArthritis = "Rheumatoid Arthritis"
    case osteoporosis = "Osteoporosis"
    case fibromyalgia = "Fibromyalgia"
    case chronicBackPain = "Chronic Back Pain"
    case gout = "Gout"
    case sciatica = "Sciatica"

    // Digestive
    case ibs = "Irritable Bowel Syndrome (IBS)"
    case crohnsDisease = "Crohn's Disease"
    case ulcerativeColitis = "Ulcerative Colitis"
    case celiacDisease = "Celiac Disease"
    case gerd = "GERD"
    case gastritis = "Gastritis"

    // Autoimmune
    case lupus = "Lupus"
    case multipleSclerosis = "Multiple Sclerosis"
    case psoriasis = "Psoriasis"
    case hashimotos = "Hashimoto's Thyroiditis"

    // Neurological
    case migraines = "Migraines"
    case epilepsy = "Epilepsy"
    case neuropathy = "Neuropathy"

    // Kidney & Liver
    case chronicKidneyDisease = "Chronic Kidney Disease"
    case kidneyStones = "Kidney Stones"
    case fattyLiverDisease = "Fatty Liver Disease"

    // Skin
    case eczema = "Eczema"
    case acne = "Acne"
    case rosacea = "Rosacea"

    // Blood
    case anemia = "Anemia"
    case ironDeficiency = "Iron Deficiency"

    // Other Common
    case allergies = "Allergies"
    case chronicFatigue = "Chronic Fatigue Syndrome"
    case tinnitus = "Tinnitus"
    case endometriosis = "Endometriosis"
    case raynauds = "Raynaud's Syndrome"
    case vertigo = "Vertigo"
    case dryEye = "Dry Eye Syndrome"
    case carpalTunnel = "Carpal Tunnel Syndrome"
    case lyme = "Lyme Disease"
    case longCovid = "Long COVID"

    static let allNames: [String] = allCases.map(\.rawValue)

    /// Search conditions by name (case-insensitive prefix/contains match)
    static func search(_ query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allNames
            .filter { $0.lowercased().contains(q) }
            .sorted { a, b in
                let aStarts = a.lowercased().hasPrefix(q)
                let bStarts = b.lowercased().hasPrefix(q)
                if aStarts != bStarts { return aStarts }
                return a < b
            }
    }
}

enum ConditionStatus: String, Codable, CaseIterable {
    case active
    case managed
    case resolved

    var displayName: String {
        switch self {
        case .active: "Active"
        case .managed: "Managed"
        case .resolved: "Resolved"
        }
    }
}

// MARK: - Vault

enum VaultFileType: String, Codable, CaseIterable {
    case pdf
    case image
    case text
    case video

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .image: "Image"
        case .text: "Text"
        case .video: "Video"
        }
    }

    var iconName: String {
        switch self {
        case .pdf: "doc.fill"
        case .image: "photo.fill"
        case .text: "doc.text.fill"
        case .video: "video.fill"
        }
    }
}

// MARK: - Diet Type

enum DietTypeOption: String, CaseIterable, Identifiable {
    case mediterranean = "Mediterranean"
    case keto = "Keto"
    case paleo = "Paleo"
    case vegan = "Vegan"
    case vegetarian = "Vegetarian"
    case wholeFoods = "Whole Foods"
    case lowCarb = "Low Carb"
    case highProtein = "High Protein"
    case dash = "DASH"
    case intermittentFasting = "Intermittent Fasting"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case antiInflammatory = "Anti-Inflammatory"
    case carnivore = "Carnivore"
    case custom = "Custom"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .mediterranean: "leaf.fill"
        case .keto: "drop.fill"
        case .paleo: "flame.fill"
        case .vegan: "leaf.circle.fill"
        case .vegetarian: "carrot.fill"
        case .wholeFoods: "basket.fill"
        case .lowCarb: "chart.bar.fill"
        case .highProtein: "bolt.fill"
        case .dash: "heart.fill"
        case .intermittentFasting: "clock.fill"
        case .glutenFree: "xmark.circle.fill"
        case .dairyFree: "drop.triangle.fill"
        case .antiInflammatory: "shield.fill"
        case .carnivore: "hare.fill"
        case .custom: "pencil"
        }
    }

    var color: Color {
        switch self {
        case .mediterranean: .green
        case .keto: .purple
        case .paleo: .orange
        case .vegan: .green
        case .vegetarian: .mint
        case .wholeFoods: .brown
        case .lowCarb: .blue
        case .highProtein: .red
        case .dash: .pink
        case .intermittentFasting: .indigo
        case .glutenFree: .orange
        case .dairyFree: .cyan
        case .antiInflammatory: .teal
        case .carnivore: .red
        case .custom: .secondary
        }
    }

    /// Match a stored string back to an option
    static func from(_ string: String) -> DietTypeOption? {
        allCases.first { $0.rawValue == string }
    }

    /// Default approved food categories for this diet type
    var defaultApproved: [FoodCategory] {
        switch self {
        case .mediterranean:
            return [.fish, .poultry, .vegetables, .fruits, .legumes, .nuts, .oliveOil, .wholeGrains, .eggs, .dairy, .herbs]
        case .keto:
            return [.redMeat, .poultry, .fish, .eggs, .dairy, .nuts, .oliveOil, .butter, .vegetables, .herbs]
        case .paleo:
            return [.redMeat, .poultry, .fish, .eggs, .vegetables, .fruits, .nuts, .oliveOil, .herbs]
        case .vegan:
            return [.vegetables, .fruits, .legumes, .nuts, .wholeGrains, .oliveOil, .tofu, .herbs]
        case .vegetarian:
            return [.vegetables, .fruits, .legumes, .nuts, .wholeGrains, .oliveOil, .eggs, .dairy, .tofu, .herbs]
        case .wholeFoods:
            return [.redMeat, .poultry, .fish, .vegetables, .fruits, .legumes, .nuts, .wholeGrains, .eggs, .dairy, .oliveOil, .herbs]
        case .lowCarb:
            return [.redMeat, .poultry, .fish, .eggs, .dairy, .vegetables, .nuts, .oliveOil, .butter, .herbs]
        case .highProtein:
            return [.redMeat, .poultry, .fish, .eggs, .dairy, .legumes, .tofu, .nuts, .wholeGrains, .herbs]
        case .dash:
            return [.poultry, .fish, .vegetables, .fruits, .legumes, .nuts, .wholeGrains, .dairy, .oliveOil, .herbs]
        case .intermittentFasting:
            return FoodCategory.allCases // No food restrictions, just timing
        case .glutenFree:
            return FoodCategory.allCases.filter { $0 != .wholeGrains && $0 != .refinedGrains }
        case .dairyFree:
            return FoodCategory.allCases.filter { $0 != .dairy && $0 != .butter }
        case .antiInflammatory:
            return [.fish, .vegetables, .fruits, .nuts, .oliveOil, .wholeGrains, .legumes, .herbs, .tofu]
        case .carnivore:
            return [.redMeat, .poultry, .fish, .eggs, .butter, .dairy]
        case .custom:
            return FoodCategory.allCases
        }
    }

    /// Default avoided food categories for this diet type
    var defaultAvoided: [FoodCategory] {
        let all = Set(FoodCategory.allCases)
        let approved = Set(defaultApproved)
        return Array(all.subtracting(approved)).sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Food Category

enum FoodCategory: String, Codable, CaseIterable, Identifiable, Comparable {
    case redMeat = "Red Meat"
    case poultry = "Poultry"
    case fish = "Fish & Seafood"
    case eggs = "Eggs"
    case dairy = "Dairy"
    case butter = "Butter & Ghee"
    case vegetables = "Vegetables"
    case fruits = "Fruits"
    case legumes = "Legumes & Beans"
    case nuts = "Nuts & Seeds"
    case wholeGrains = "Whole Grains"
    case refinedGrains = "Refined Grains"
    case oliveOil = "Olive Oil"
    case tofu = "Tofu & Soy"
    case sugar = "Added Sugar"
    case processedFoods = "Processed Foods"
    case alcohol = "Alcohol"
    case herbs = "Herbs & Spices"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .redMeat: "flame.fill"
        case .poultry: "bird.fill"
        case .fish: "fish.fill"
        case .eggs: "oval.fill"
        case .dairy: "cup.and.saucer.fill"
        case .butter: "rectangle.fill"
        case .vegetables: "leaf.fill"
        case .fruits: "apple.logo"
        case .legumes: "circle.grid.3x3.fill"
        case .nuts: "tree.fill"
        case .wholeGrains: "wheat.bundle.fill"
        case .refinedGrains: "square.stack.fill"
        case .oliveOil: "drop.fill"
        case .tofu: "square.fill"
        case .sugar: "cube.fill"
        case .processedFoods: "shippingbox.fill"
        case .alcohol: "wineglass.fill"
        case .herbs: "leaf.arrow.circlepath"
        }
    }

    static func < (lhs: FoodCategory, rhs: FoodCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Grid Section (for ordering habits/meds on daily grid)

enum GridSection: String, Codable, CaseIterable {
    case any
    case morning
    case afternoon
    case evening
    case night

    var displayName: String {
        switch self {
        case .any: "Any"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }
}

// MARK: - Chat

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Codable, Identifiable {
    var id: UUID = UUID()
    var role: ChatRole
    var content: String
    var timestamp: Date = Date()
}

// MARK: - Time Range (for chart filtering)

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }

    var startDate: Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}

// MARK: - Weight/Temp Units

enum WeightUnit: String, Codable, CaseIterable {
    case kg
    case lbs

    func convert(_ kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lbs: kg * 2.20462
        }
    }

    func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lbs: value / 2.20462
        }
    }

    var symbol: String {
        switch self {
        case .kg: "kg"
        case .lbs: "lbs"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius
    case fahrenheit

    func convert(_ celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    func toCelsius(_ value: Double) -> Double {
        switch self {
        case .celsius: value
        case .fahrenheit: (value - 32) * 5 / 9
        }
    }

    var symbol: String {
        switch self {
        case .celsius: "C"
        case .fahrenheit: "F"
        }
    }
}

enum ClaudeModel: String, Codable, CaseIterable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-6"

    var displayName: String {
        switch self {
        case .haiku: "Haiku"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        }
    }

    var subtitle: String {
        switch self {
        case .haiku: "Fastest, lower cost"
        case .sonnet: "Balanced (recommended)"
        case .opus: "Most capable, higher cost"
        }
    }
}
