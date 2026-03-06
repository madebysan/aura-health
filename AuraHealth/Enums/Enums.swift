import Foundation

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

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .csv: "CSV Import"
        case .whoop: "WHOOP"
        case .appleHealth: "Apple Health"
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

// MARK: - Grid Section (for ordering habits/meds on daily grid)

enum GridSection: String, Codable, CaseIterable {
    case morning
    case afternoon
    case evening
    case night

    var displayName: String {
        switch self {
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
