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
        case .recovery: "arrow.counterclockwise.heart"
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
