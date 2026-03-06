import Foundation
import SwiftUI

/// Body-system grouping and reference data for biomarkers
enum BodySystem: String, CaseIterable, Identifiable {
    case heart = "Heart"
    case metabolic = "Metabolic"
    case liver = "Liver"
    case kidney = "Kidney"
    case thyroid = "Thyroid"
    case blood = "Blood"
    case hormones = "Hormones"
    case inflammation = "Inflammation"
    case vitamins = "Vitamins & Minerals"
    case other = "Other"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .heart: "heart.fill"
        case .metabolic: "flame.fill"
        case .liver: "cross.vial.fill"
        case .kidney: "drop.fill"
        case .thyroid: "waveform.path.ecg"
        case .blood: "drop.triangle.fill"
        case .hormones: "bolt.heart.fill"
        case .inflammation: "exclamationmark.shield.fill"
        case .vitamins: "leaf.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .heart: "red"
        case .metabolic: "orange"
        case .liver: "green"
        case .kidney: "blue"
        case .thyroid: "purple"
        case .blood: "pink"
        case .hormones: "indigo"
        case .inflammation: "yellow"
        case .vitamins: "teal"
        case .other: "gray"
        }
    }

    var swiftColor: Color {
        switch self {
        case .heart: .red
        case .metabolic: .orange
        case .liver: .green
        case .kidney: .blue
        case .thyroid: .purple
        case .blood: .pink
        case .hormones: .indigo
        case .inflammation: .yellow
        case .vitamins: .teal
        case .other: .gray
        }
    }
}

struct BiomarkerInfo {
    let name: String
    let system: BodySystem
    let unit: String
    let refMin: Double
    let refMax: Double
    let description: String
    let whyItMatters: String
    let ifOutOfRange: String
}

/// Known biomarker reference database
enum BiomarkerReference {

    /// Classify a marker name to a body system
    static func system(for marker: String) -> BodySystem {
        let lower = marker.lowercased()

        // Heart / Lipids
        if lower.contains("cholesterol") || lower.contains("ldl") || lower.contains("hdl")
            || lower.contains("triglyceride") || lower.contains("lipoprotein")
            || lower.contains("apolipoprotein") {
            return .heart
        }
        // Metabolic
        if lower.contains("glucose") || lower.contains("hba1c") || lower.contains("a1c")
            || lower.contains("insulin") || lower.contains("homa") {
            return .metabolic
        }
        // Liver
        if lower.contains("alt") || lower.contains("ast") || lower.contains("ggt")
            || lower.contains("bilirubin") || lower.contains("albumin")
            || lower.contains("alkaline phosphatase") {
            return .liver
        }
        // Kidney
        if lower.contains("creatinine") || lower.contains("egfr") || lower.contains("bun")
            || lower.contains("urea") || lower.contains("uric acid")
            || lower.contains("cystatin") {
            return .kidney
        }
        // Thyroid
        if lower.contains("tsh") || lower.contains("t3") || lower.contains("t4")
            || lower.contains("thyroid") {
            return .thyroid
        }
        // Blood
        if lower.contains("hemoglobin") || lower.contains("hematocrit")
            || lower.contains("rbc") || lower.contains("wbc") || lower.contains("platelet")
            || lower.contains("mcv") || lower.contains("mch") || lower.contains("ferritin")
            || lower.contains("iron") || lower.contains("transferrin") {
            return .blood
        }
        // Hormones
        if lower.contains("testosterone") || lower.contains("estrogen") || lower.contains("cortisol")
            || lower.contains("dhea") || lower.contains("shbg") || lower.contains("progesterone")
            || lower.contains("prolactin") || lower.contains("igf") {
            return .hormones
        }
        // Inflammation
        if lower.contains("crp") || lower.contains("esr") || lower.contains("homocysteine")
            || lower.contains("fibrinogen") || lower.contains("il-6") || lower.contains("tnf") {
            return .inflammation
        }
        // Vitamins
        if lower.contains("vitamin") || lower.contains("folate") || lower.contains("b12")
            || lower.contains("zinc") || lower.contains("magnesium") || lower.contains("selenium")
            || lower.contains("omega") {
            return .vitamins
        }

        return .other
    }

    /// Get detailed info for a known marker
    static func info(for marker: String) -> BiomarkerInfo? {
        knownMarkers[marker.lowercased()]
    }

    private static let knownMarkers: [String: BiomarkerInfo] = [
        "total cholesterol": BiomarkerInfo(
            name: "Total Cholesterol", system: .heart, unit: "mg/dL", refMin: 125, refMax: 200,
            description: "Total amount of cholesterol in your blood, including LDL and HDL.",
            whyItMatters: "High total cholesterol increases risk of heart disease and stroke.",
            ifOutOfRange: "Focus on reducing saturated fats, increase fiber intake, and exercise regularly."
        ),
        "ldl cholesterol": BiomarkerInfo(
            name: "LDL Cholesterol", system: .heart, unit: "mg/dL", refMin: 0, refMax: 100,
            description: "Low-density lipoprotein — the 'bad' cholesterol that builds up in arteries.",
            whyItMatters: "Elevated LDL is a primary driver of atherosclerosis and cardiovascular disease.",
            ifOutOfRange: "Reduce trans fats, increase soluble fiber, consider statins if lifestyle changes aren't enough."
        ),
        "hdl cholesterol": BiomarkerInfo(
            name: "HDL Cholesterol", system: .heart, unit: "mg/dL", refMin: 40, refMax: 100,
            description: "High-density lipoprotein — the 'good' cholesterol that removes LDL from arteries.",
            whyItMatters: "Higher HDL is protective against heart disease.",
            ifOutOfRange: "Exercise regularly, consume healthy fats (olive oil, nuts), avoid smoking."
        ),
        "fasting glucose": BiomarkerInfo(
            name: "Fasting Glucose", system: .metabolic, unit: "mg/dL", refMin: 70, refMax: 100,
            description: "Blood sugar level after 8+ hours of fasting.",
            whyItMatters: "Elevated fasting glucose indicates insulin resistance or diabetes risk.",
            ifOutOfRange: "Reduce refined carbs and sugar, increase physical activity, monitor regularly."
        ),
        "hba1c": BiomarkerInfo(
            name: "HbA1c", system: .metabolic, unit: "%", refMin: 4.0, refMax: 5.7,
            description: "Average blood sugar over the past 2-3 months.",
            whyItMatters: "The gold standard for long-term glucose control and diabetes diagnosis.",
            ifOutOfRange: "Work with your doctor on diet, exercise, and medication adjustments."
        ),
        "vitamin d": BiomarkerInfo(
            name: "Vitamin D", system: .vitamins, unit: "ng/mL", refMin: 30, refMax: 100,
            description: "Essential vitamin for bone health, immune function, and mood.",
            whyItMatters: "Deficiency is extremely common and linked to fatigue, depression, and weak bones.",
            ifOutOfRange: "Supplement with D3 (2000-5000 IU daily), get sun exposure, eat fatty fish."
        ),
        "crp": BiomarkerInfo(
            name: "CRP", system: .inflammation, unit: "mg/L", refMin: 0, refMax: 3.0,
            description: "C-reactive protein — a marker of systemic inflammation.",
            whyItMatters: "Elevated CRP indicates chronic inflammation, which drives many diseases.",
            ifOutOfRange: "Anti-inflammatory diet, omega-3s, reduce stress, improve sleep."
        ),
        "testosterone": BiomarkerInfo(
            name: "Testosterone", system: .hormones, unit: "ng/dL", refMin: 300, refMax: 1000,
            description: "Primary male sex hormone, also important for women in smaller amounts.",
            whyItMatters: "Affects energy, muscle mass, bone density, mood, and libido.",
            ifOutOfRange: "Optimize sleep, reduce stress, strength train, check with endocrinologist."
        ),
    ]
}
