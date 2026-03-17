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
            || lower.contains("apolipoprotein") || lower.contains("apob") {
            return .heart
        }
        // Metabolic
        if lower.contains("glucose") || lower.contains("hba1c") || lower.contains("a1c")
            || lower.contains("insulin") || lower.contains("homa")
            || lower == "carbon dioxide" {
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
            || lower.contains("cystatin") || lower == "sodium" || lower == "potassium"
            || lower == "chloride" || lower == "calcium" {
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
            || lower.contains("iron") || lower.contains("transferrin")
            || lower == "rdw" || lower == "mpv" {
            return .blood
        }
        // Hormones
        if lower.contains("testosterone") || lower.contains("estrogen") || lower.contains("cortisol")
            || lower.contains("dhea") || lower.contains("shbg") || lower.contains("progesterone")
            || lower.contains("prolactin") || lower.contains("igf") || lower.contains("estradiol")
            || lower == "lh" || lower == "fsh" || lower == "psa" || lower == "insulin" {
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

    /// Get detailed info for a known marker (supports aliases like "ApoB" → "Apolipoprotein B")
    static func info(for marker: String) -> BiomarkerInfo? {
        let key = canonicalName(for: marker).lowercased()
        return knownMarkers[key]
    }

    /// Resolve common aliases to canonical marker names
    static func canonicalName(for marker: String) -> String {
        let lower = marker.lowercased().trimmingCharacters(in: .whitespaces)
        return aliases[lower] ?? marker
    }

    private static let aliases: [String: String] = [
        "apob": "Apolipoprotein B",
        "apo b": "Apolipoprotein B",
        "apo-b": "Apolipoprotein B",
        "ldl": "LDL Cholesterol",
        "ldl-c": "LDL Cholesterol",
        "hdl": "HDL Cholesterol",
        "hdl-c": "HDL Cholesterol",
        "tc": "Total Cholesterol",
        "tg": "Triglycerides",
        "trigs": "Triglycerides",
        "hba1c": "HbA1c",
        "a1c": "HbA1c",
        "hemoglobin a1c": "HbA1c",
        "fasting glucose": "Glucose",
        "fbs": "Glucose",
        "egfr": "eGFR",
        "gfr": "eGFR",
        "ast": "AST",
        "sgot": "AST",
        "alt": "ALT",
        "sgpt": "ALT",
        "alp": "Alkaline Phosphatase",
        "alk phos": "Alkaline Phosphatase",
        "t3": "Free T3",
        "ft3": "Free T3",
        "t4": "Free T4",
        "ft4": "Free T4",
        "tsh": "TSH",
        "wbc": "WBC",
        "rbc": "RBC",
        "hgb": "Hemoglobin",
        "hct": "Hematocrit",
        "plt": "Platelets",
        "mcv": "MCV",
        "mch": "MCH",
        "mchc": "MCHC",
        "rdw": "RDW",
        "bun": "BUN",
        "crp": "hs-CRP",
        "hscrp": "hs-CRP",
        "hs-crp": "hs-CRP",
        "c-reactive protein": "hs-CRP",
        "vit d": "Vitamin D",
        "vitamin d3": "Vitamin D",
        "25-oh vitamin d": "Vitamin D",
        "vit b12": "Vitamin B12",
        "b12": "Vitamin B12",
        "shbg": "SHBG",
        "lh": "LH",
        "psa": "PSA",
        "na": "Sodium",
        "k": "Potassium",
        "cl": "Chloride",
        "ca": "Calcium",
        "co2": "Carbon Dioxide",
        "bicarb": "Carbon Dioxide",
        "total protein": "Total Protein",
        "tp": "Total Protein",
        "total test": "Testosterone, Total",
        "total testosterone": "Testosterone, Total",
        "free test": "Free Testosterone",
        "free t": "Free Testosterone",
    ]

    private static let knownMarkers: [String: BiomarkerInfo] = [
        // MARK: Heart / Lipids
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
        "non-hdl cholesterol": BiomarkerInfo(
            name: "Non-HDL Cholesterol", system: .heart, unit: "mg/dL", refMin: 0, refMax: 130,
            description: "Total cholesterol minus HDL — captures all atherogenic particles including LDL, VLDL, and Lp(a).",
            whyItMatters: "A better predictor of cardiovascular risk than LDL alone because it includes all 'bad' cholesterol types.",
            ifOutOfRange: "Same strategies as LDL: reduce saturated fats, exercise, increase fiber. Discuss with your doctor if persistently elevated."
        ),
        "triglycerides": BiomarkerInfo(
            name: "Triglycerides", system: .heart, unit: "mg/dL", refMin: 0, refMax: 150,
            description: "Fat molecules in your blood, primarily from dietary fats and excess calories converted by the liver.",
            whyItMatters: "High triglycerides increase risk of heart disease and pancreatitis. Often elevated alongside insulin resistance.",
            ifOutOfRange: "Reduce sugar and refined carbs, limit alcohol, increase omega-3 fatty acids, exercise regularly."
        ),
        "apolipoprotein b": BiomarkerInfo(
            name: "Apolipoprotein B", system: .heart, unit: "mg/dL", refMin: 0, refMax: 90,
            description: "A protein found on every atherogenic lipoprotein particle (LDL, VLDL, Lp(a)). Each particle has exactly one ApoB molecule, making it a direct count of particles that can enter artery walls.",
            whyItMatters: "Considered the single best blood marker for cardiovascular risk — better than LDL cholesterol. It measures the actual number of dangerous particles, not just the cholesterol they carry.",
            ifOutOfRange: "Diet optimization (reduce saturated fat, increase fiber), exercise, and potentially statin therapy. Optimal is below 80 mg/dL; ideal for high-risk patients is below 60."
        ),
        // MARK: Metabolic
        "glucose": BiomarkerInfo(
            name: "Glucose", system: .metabolic, unit: "mg/dL", refMin: 65, refMax: 99,
            description: "Blood sugar level, ideally measured after fasting. Your body's primary energy source.",
            whyItMatters: "Elevated fasting glucose indicates insulin resistance or diabetes risk. Chronically high glucose damages blood vessels and organs.",
            ifOutOfRange: "Reduce refined carbs and sugar, increase physical activity, monitor regularly. Retest fasting if borderline."
        ),
        "fasting glucose": BiomarkerInfo(
            name: "Fasting Glucose", system: .metabolic, unit: "mg/dL", refMin: 70, refMax: 100,
            description: "Blood sugar level after 8+ hours of fasting.",
            whyItMatters: "Elevated fasting glucose indicates insulin resistance or diabetes risk.",
            ifOutOfRange: "Reduce refined carbs and sugar, increase physical activity, monitor regularly."
        ),
        "hba1c": BiomarkerInfo(
            name: "HbA1c", system: .metabolic, unit: "%", refMin: 4.0, refMax: 5.7,
            description: "Glycated hemoglobin — reflects your average blood sugar over the past 2–3 months.",
            whyItMatters: "The gold standard for long-term glucose control and diabetes diagnosis. Below 5.7% is normal, 5.7–6.4% is prediabetic.",
            ifOutOfRange: "Work with your doctor on diet, exercise, and medication adjustments. Even small reductions reduce complication risk."
        ),
        "insulin": BiomarkerInfo(
            name: "Insulin", system: .metabolic, unit: "uIU/mL", refMin: 2.6, refMax: 18.4,
            description: "Hormone produced by the pancreas that regulates blood sugar by moving glucose into cells.",
            whyItMatters: "High fasting insulin is an early sign of insulin resistance — often years before glucose rises. It's a key driver of metabolic syndrome, weight gain, and inflammation.",
            ifOutOfRange: "Reduce refined carbs, exercise (especially strength training), improve sleep. Optimal fasting insulin is 3–8 uIU/mL."
        ),
        "carbon dioxide": BiomarkerInfo(
            name: "Carbon Dioxide (CO2)", system: .metabolic, unit: "mmol/L", refMin: 20, refMax: 32,
            description: "Bicarbonate level in blood — reflects your body's acid-base balance.",
            whyItMatters: "Abnormal levels can indicate respiratory problems, kidney issues, or metabolic acidosis/alkalosis.",
            ifOutOfRange: "Low CO2 may indicate metabolic acidosis. Discuss with your doctor — it's rarely actionable on its own."
        ),
        // MARK: Liver
        "ast": BiomarkerInfo(
            name: "AST (SGOT)", system: .liver, unit: "U/L", refMin: 10, refMax: 40,
            description: "Aspartate aminotransferase — an enzyme found in the liver, heart, and muscles. Released into blood when these tissues are damaged.",
            whyItMatters: "Elevated AST can indicate liver damage, but also muscle injury or heart problems. Best interpreted alongside ALT.",
            ifOutOfRange: "Reduce alcohol, avoid hepatotoxic medications, retest after intense exercise. If persistently elevated, investigate liver health."
        ),
        "alt": BiomarkerInfo(
            name: "ALT (SGPT)", system: .liver, unit: "U/L", refMin: 7, refMax: 46,
            description: "Alanine aminotransferase — a liver-specific enzyme. More specific to liver damage than AST.",
            whyItMatters: "Elevated ALT is often the first sign of liver stress from fatty liver disease, alcohol, or medications.",
            ifOutOfRange: "Limit alcohol, review medications with your doctor, address fatty liver through diet and exercise."
        ),
        "alkaline phosphatase": BiomarkerInfo(
            name: "Alkaline Phosphatase", system: .liver, unit: "U/L", refMin: 36, refMax: 130,
            description: "An enzyme found in the liver, bones, kidneys, and digestive system.",
            whyItMatters: "Elevated levels may indicate bile duct obstruction, liver disease, or bone disorders. Low levels are rare but can indicate zinc or magnesium deficiency.",
            ifOutOfRange: "Further testing needed to determine the source — liver imaging or bone density scan may be appropriate."
        ),
        "bilirubin, total": BiomarkerInfo(
            name: "Bilirubin (Total)", system: .liver, unit: "mg/dL", refMin: 0.2, refMax: 1.2,
            description: "A yellow pigment produced when red blood cells break down. Processed by the liver and excreted in bile.",
            whyItMatters: "Elevated bilirubin can indicate liver dysfunction, bile duct obstruction, or excessive red blood cell breakdown. Mildly elevated levels (Gilbert's syndrome) are common and benign.",
            ifOutOfRange: "If mildly elevated with normal liver enzymes, likely Gilbert's syndrome (harmless). If accompanied by elevated liver enzymes, further investigation needed."
        ),
        "albumin": BiomarkerInfo(
            name: "Albumin", system: .liver, unit: "g/dL", refMin: 3.6, refMax: 5.1,
            description: "The most abundant protein in blood, made by the liver. Carries hormones, vitamins, and enzymes throughout the body.",
            whyItMatters: "Low albumin can indicate liver disease, kidney disease, malnutrition, or chronic inflammation. It's a marker of overall health status.",
            ifOutOfRange: "Ensure adequate protein intake. If low, investigate liver and kidney function. Chronic illness and inflammation can also lower it."
        ),
        "protein, total": BiomarkerInfo(
            name: "Total Protein", system: .liver, unit: "g/dL", refMin: 6.0, refMax: 8.5,
            description: "Combined albumin and globulin in your blood. Reflects liver synthetic function and immune activity.",
            whyItMatters: "Abnormal levels can indicate liver disease, kidney problems, immune disorders, or nutritional deficiencies.",
            ifOutOfRange: "Look at albumin and globulin individually. High globulin may indicate chronic inflammation or infection."
        ),
        "globulin": BiomarkerInfo(
            name: "Globulin", system: .liver, unit: "g/dL", refMin: 1.9, refMax: 3.7,
            description: "A group of proteins made by the liver and immune system, including antibodies.",
            whyItMatters: "High globulin can indicate chronic inflammation, infection, or autoimmune disease. Low levels may suggest immune deficiency.",
            ifOutOfRange: "If elevated, further workup for inflammation or immune conditions. If low, evaluate immune function."
        ),
        // MARK: Kidney
        "creatinine": BiomarkerInfo(
            name: "Creatinine", system: .kidney, unit: "mg/dL", refMin: 0.6, refMax: 1.27,
            description: "A waste product from muscle metabolism, filtered by the kidneys. Creatinine levels reflect kidney filtration capacity.",
            whyItMatters: "Rising creatinine suggests declining kidney function. It's also influenced by muscle mass — muscular people naturally run higher.",
            ifOutOfRange: "Stay hydrated, avoid NSAIDs, monitor over time. If persistently elevated, a kidney function workup is needed."
        ),
        "egfr": BiomarkerInfo(
            name: "eGFR", system: .kidney, unit: "mL/min/1.73m2", refMin: 60, refMax: 120,
            description: "Estimated glomerular filtration rate — calculated from creatinine, age, and sex. Estimates how well your kidneys filter blood.",
            whyItMatters: "The primary measure of kidney function. Below 60 sustained for 3+ months indicates chronic kidney disease.",
            ifOutOfRange: "Control blood pressure and blood sugar, reduce salt intake, stay hydrated, avoid nephrotoxic drugs."
        ),
        "bun": BiomarkerInfo(
            name: "BUN", system: .kidney, unit: "mg/dL", refMin: 6, refMax: 25,
            description: "Blood urea nitrogen — a waste product from protein metabolism, filtered by the kidneys.",
            whyItMatters: "Elevated BUN can indicate dehydration, high protein intake, or reduced kidney function. Best interpreted alongside creatinine.",
            ifOutOfRange: "Ensure adequate hydration. If elevated with creatinine, evaluate kidney function. High protein diets can raise BUN."
        ),
        "cystatin c": BiomarkerInfo(
            name: "Cystatin C", system: .kidney, unit: "mg/L", refMin: 0.6, refMax: 1.0,
            description: "A protein produced by all cells, filtered by the kidneys. Unlike creatinine, it's not affected by muscle mass.",
            whyItMatters: "A more accurate kidney function marker than creatinine, especially for people with unusual muscle mass (very fit or very sedentary).",
            ifOutOfRange: "Same as creatinine — focus on kidney-protective lifestyle. Useful for confirming borderline creatinine/eGFR results."
        ),
        "sodium": BiomarkerInfo(
            name: "Sodium", system: .kidney, unit: "mmol/L", refMin: 134, refMax: 146,
            description: "An essential electrolyte that regulates fluid balance, blood pressure, and nerve/muscle function.",
            whyItMatters: "Low sodium (hyponatremia) can cause confusion, seizures, and is surprisingly common. High sodium (hypernatremia) usually indicates dehydration.",
            ifOutOfRange: "Low: may indicate overhydration, certain medications, or hormonal issues. High: increase fluid intake. Both extremes warrant medical evaluation."
        ),
        "potassium": BiomarkerInfo(
            name: "Potassium", system: .kidney, unit: "mmol/L", refMin: 3.5, refMax: 5.3,
            description: "An essential electrolyte critical for heart rhythm, muscle contraction, and nerve signaling.",
            whyItMatters: "Both high and low potassium can cause dangerous heart rhythm abnormalities. Kidney disease, certain medications, and diet all affect levels.",
            ifOutOfRange: "High: limit potassium-rich foods, review medications. Low: increase dietary potassium (bananas, potatoes, leafy greens). Both need monitoring."
        ),
        "chloride": BiomarkerInfo(
            name: "Chloride", system: .kidney, unit: "mmol/L", refMin: 96, refMax: 110,
            description: "An electrolyte that works with sodium and potassium to maintain fluid balance and acid-base equilibrium.",
            whyItMatters: "Abnormal chloride usually moves in tandem with sodium. Isolated changes can indicate acid-base disorders.",
            ifOutOfRange: "Rarely addressed alone — usually treated by correcting the underlying sodium or acid-base imbalance."
        ),
        "calcium": BiomarkerInfo(
            name: "Calcium", system: .kidney, unit: "mg/dL", refMin: 8.6, refMax: 10.3,
            description: "Essential for bones, teeth, muscle contraction, nerve signaling, and blood clotting. Tightly regulated by parathyroid hormone and vitamin D.",
            whyItMatters: "High calcium (hypercalcemia) can indicate parathyroid problems or cancer. Low calcium is often linked to vitamin D deficiency.",
            ifOutOfRange: "High: check parathyroid hormone and vitamin D. Low: supplement vitamin D, ensure adequate dietary calcium."
        ),
        // MARK: Thyroid
        "tsh": BiomarkerInfo(
            name: "TSH", system: .thyroid, unit: "mIU/L", refMin: 0.4, refMax: 4.5,
            description: "Thyroid-stimulating hormone — produced by the pituitary gland to signal the thyroid to make T3 and T4.",
            whyItMatters: "The most sensitive screening test for thyroid disorders. High TSH suggests hypothyroidism (underactive), low TSH suggests hyperthyroidism (overactive).",
            ifOutOfRange: "Mildly elevated TSH (4.5–10) with normal T4: subclinical hypothyroidism — monitor or treat based on symptoms. Above 10 or with low T4: likely needs treatment."
        ),
        "free t4": BiomarkerInfo(
            name: "Free T4", system: .thyroid, unit: "ng/dL", refMin: 0.8, refMax: 1.8,
            description: "The unbound, active form of thyroxine — the main hormone produced by the thyroid gland.",
            whyItMatters: "Low free T4 with high TSH confirms hypothyroidism. High free T4 with low TSH confirms hyperthyroidism.",
            ifOutOfRange: "Interpret alongside TSH. If both are abnormal, thyroid medication may be needed. See an endocrinologist."
        ),
        "free t3": BiomarkerInfo(
            name: "Free T3", system: .thyroid, unit: "pg/mL", refMin: 2.3, refMax: 4.2,
            description: "The unbound, active form of triiodothyronine — the most potent thyroid hormone. Most T3 is converted from T4 in tissues.",
            whyItMatters: "Low T3 can cause fatigue and brain fog even with normal TSH and T4. Poor T4-to-T3 conversion is common with stress, illness, or low selenium/zinc.",
            ifOutOfRange: "Ensure adequate selenium, zinc, and iron. Reduce chronic stress. If persistently low, discuss with your doctor."
        ),
        "t4": BiomarkerInfo(
            name: "T4 (Total)", system: .thyroid, unit: "ug/dL", refMin: 4.5, refMax: 12.0,
            description: "Total thyroxine — includes both bound and unbound T4. Less accurate than free T4 because binding proteins can vary.",
            whyItMatters: "Provides a general picture of thyroid output. Free T4 is preferred for diagnosis, but total T4 adds context.",
            ifOutOfRange: "Interpret alongside TSH and free T4. Estrogen, pregnancy, and certain medications can alter binding proteins and affect total T4."
        ),
        // MARK: Blood / CBC
        "wbc": BiomarkerInfo(
            name: "WBC (White Blood Cells)", system: .blood, unit: "x10E3/uL", refMin: 3.4, refMax: 10.8,
            description: "White blood cells are your immune system's soldiers. They fight infections, respond to allergens, and patrol for abnormal cells.",
            whyItMatters: "Elevated WBC often indicates infection, inflammation, or stress. Persistently low WBC may suggest immune suppression or bone marrow issues.",
            ifOutOfRange: "Mild elevations during illness are normal. If persistently elevated without illness, investigate for chronic inflammation. Low counts need further workup."
        ),
        "rbc": BiomarkerInfo(
            name: "RBC (Red Blood Cells)", system: .blood, unit: "x10E6/uL", refMin: 4.2, refMax: 5.8,
            description: "Red blood cells carry oxygen from lungs to tissues and return carbon dioxide for exhalation.",
            whyItMatters: "Low RBC (anemia) causes fatigue and weakness. High RBC may indicate dehydration, lung disease, or polycythemia.",
            ifOutOfRange: "Low: check iron, B12, and folate. High: ensure adequate hydration, check for underlying causes."
        ),
        "hemoglobin": BiomarkerInfo(
            name: "Hemoglobin", system: .blood, unit: "g/dL", refMin: 13.0, refMax: 17.7,
            description: "The iron-containing protein in red blood cells that binds and carries oxygen.",
            whyItMatters: "Low hemoglobin is the definition of anemia — causes fatigue, shortness of breath, and reduced exercise capacity. High hemoglobin may indicate dehydration or polycythemia.",
            ifOutOfRange: "Low: investigate iron deficiency, B12, or chronic disease. High: stay hydrated, check for altitude effects or underlying conditions."
        ),
        "hematocrit": BiomarkerInfo(
            name: "Hematocrit", system: .blood, unit: "%", refMin: 37.5, refMax: 52.0,
            description: "The percentage of blood volume occupied by red blood cells. Closely tracks hemoglobin.",
            whyItMatters: "High hematocrit thickens blood and increases clotting risk. Low hematocrit indicates anemia.",
            ifOutOfRange: "Similar to hemoglobin — investigate iron, hydration, and underlying causes. Very high levels may need therapeutic phlebotomy."
        ),
        "mcv": BiomarkerInfo(
            name: "MCV", system: .blood, unit: "fL", refMin: 79, refMax: 100,
            description: "Mean corpuscular volume — the average size of your red blood cells.",
            whyItMatters: "Small cells (low MCV) suggest iron deficiency. Large cells (high MCV) suggest B12 or folate deficiency, or alcohol use.",
            ifOutOfRange: "Low: check iron and ferritin. High: check B12, folate, and alcohol intake. Helps classify the type of anemia."
        ),
        "mch": BiomarkerInfo(
            name: "MCH", system: .blood, unit: "pg", refMin: 26.6, refMax: 33.0,
            description: "Mean corpuscular hemoglobin — the average amount of hemoglobin per red blood cell.",
            whyItMatters: "Generally tracks with MCV. Low MCH indicates iron deficiency, high MCH suggests B12 or folate deficiency.",
            ifOutOfRange: "Same as MCV — check iron, B12, and folate based on direction of abnormality."
        ),
        "mchc": BiomarkerInfo(
            name: "MCHC", system: .blood, unit: "g/dL", refMin: 31.5, refMax: 35.7,
            description: "Mean corpuscular hemoglobin concentration — the average concentration of hemoglobin within red blood cells.",
            whyItMatters: "Low MCHC confirms iron deficiency anemia (pale cells). Rarely elevated — may indicate spherocytosis.",
            ifOutOfRange: "Low: check iron studies. Elevated: relatively rare, may indicate a red blood cell membrane disorder."
        ),
        "rdw": BiomarkerInfo(
            name: "RDW", system: .blood, unit: "%", refMin: 11.0, refMax: 15.5,
            description: "Red cell distribution width — measures variation in red blood cell size.",
            whyItMatters: "High RDW indicates mixed cell sizes, often seen in early iron or B12 deficiency before other markers change. Also linked to cardiovascular risk.",
            ifOutOfRange: "Check iron, B12, and folate. An elevated RDW with normal MCV can be an early warning of developing deficiency."
        ),
        "platelets": BiomarkerInfo(
            name: "Platelets", system: .blood, unit: "x10E3/uL", refMin: 140, refMax: 400,
            description: "Cell fragments that form blood clots to stop bleeding. Produced in bone marrow.",
            whyItMatters: "Low platelets (thrombocytopenia) increase bleeding risk. High platelets may indicate inflammation, iron deficiency, or myeloproliferative disorders.",
            ifOutOfRange: "Mild fluctuations are common. Persistently low: evaluate for autoimmune causes or medication effects. Persistently high: check iron and inflammatory markers."
        ),
        "ferritin": BiomarkerInfo(
            name: "Ferritin", system: .blood, unit: "ng/mL", refMin: 30, refMax: 400,
            description: "The body's iron storage protein. The most sensitive marker for iron status.",
            whyItMatters: "Low ferritin is the earliest sign of iron depletion — often causes fatigue before hemoglobin drops. Elevated ferritin can indicate inflammation, liver disease, or iron overload.",
            ifOutOfRange: "Low: supplement iron (with vitamin C for absorption), eat red meat or iron-rich foods. High: check for inflammation first. Optimal is 50–150 ng/mL."
        ),
        // MARK: Hormones
        "testosterone, total": BiomarkerInfo(
            name: "Total Testosterone", system: .hormones, unit: "ng/dL", refMin: 250, refMax: 1100,
            description: "Total testosterone includes both bound (to SHBG and albumin) and free testosterone.",
            whyItMatters: "Affects energy, muscle mass, bone density, mood, libido, and cognitive function in both men and women.",
            ifOutOfRange: "Low: optimize sleep, reduce stress, strength train, lose excess body fat. If symptoms persist, see an endocrinologist. Check SHBG and free T to get the full picture."
        ),
        "testosterone": BiomarkerInfo(
            name: "Testosterone", system: .hormones, unit: "ng/dL", refMin: 300, refMax: 1000,
            description: "Primary male sex hormone, also important for women in smaller amounts.",
            whyItMatters: "Affects energy, muscle mass, bone density, mood, and libido.",
            ifOutOfRange: "Optimize sleep, reduce stress, strength train, check with endocrinologist."
        ),
        "free testosterone": BiomarkerInfo(
            name: "Free Testosterone", system: .hormones, unit: "pg/mL", refMin: 50, refMax: 210,
            description: "The unbound, biologically active form of testosterone — only 2–3% of total testosterone is free.",
            whyItMatters: "Free T is what your body actually uses. You can have normal total T but low free T if SHBG is high, which causes symptoms of low testosterone.",
            ifOutOfRange: "If low with high SHBG: address SHBG-raising factors (excess estrogen, liver issues, low carb diets). If low with low total T: overall testosterone production is the issue."
        ),
        "estradiol": BiomarkerInfo(
            name: "Estradiol (E2)", system: .hormones, unit: "pg/mL", refMin: 11, refMax: 43,
            description: "The primary form of estrogen. In men, it's converted from testosterone by aromatase and is essential for bone health and brain function.",
            whyItMatters: "In men, both too low and too high estradiol cause problems — low impairs bone density and mood, high causes water retention and gynecomastia.",
            ifOutOfRange: "High: often from excess body fat (more aromatase activity) — lose weight, reduce alcohol. Low: may need evaluation if on testosterone therapy."
        ),
        "shbg": BiomarkerInfo(
            name: "SHBG", system: .hormones, unit: "nmol/L", refMin: 16.5, refMax: 76.0,
            description: "Sex hormone-binding globulin — a protein that binds testosterone and estradiol, making them inactive.",
            whyItMatters: "High SHBG reduces free testosterone even when total T is normal. Low SHBG may increase free T but also free estradiol.",
            ifOutOfRange: "High: often caused by hyperthyroidism, liver disease, or estrogen excess. Low: associated with insulin resistance, obesity, and hypothyroidism."
        ),
        "lh": BiomarkerInfo(
            name: "LH (Luteinizing Hormone)", system: .hormones, unit: "IU/L", refMin: 1.7, refMax: 8.6,
            description: "Produced by the pituitary gland — stimulates the testes to produce testosterone (or ovaries to produce estrogen).",
            whyItMatters: "High LH with low testosterone indicates the testes aren't responding (primary hypogonadism). Low LH with low T indicates the pituitary isn't signaling properly (secondary hypogonadism).",
            ifOutOfRange: "Interpret alongside testosterone. Helps determine whether low T is a testicular or pituitary problem."
        ),
        "psa": BiomarkerInfo(
            name: "PSA", system: .hormones, unit: "ng/mL", refMin: 0, refMax: 4.0,
            description: "Prostate-specific antigen — a protein produced by the prostate gland. Used as a screening marker for prostate health.",
            whyItMatters: "Elevated PSA can indicate prostate cancer, but also benign enlargement (BPH), infection, or recent activity. Trending over time is more informative than a single value.",
            ifOutOfRange: "Don't panic — most elevated PSAs are not cancer. Retest, track the trend, and discuss with a urologist if rising."
        ),
        // MARK: Inflammation
        "hs-crp": BiomarkerInfo(
            name: "hs-CRP", system: .inflammation, unit: "mg/L", refMin: 0, refMax: 1.0,
            description: "High-sensitivity C-reactive protein — detects low-grade chronic inflammation that standard CRP misses.",
            whyItMatters: "The best blood marker for cardiovascular inflammation. Below 1.0 is low risk, 1–3 is moderate, above 3.0 is high risk. Predicts heart attacks independently of cholesterol.",
            ifOutOfRange: "Anti-inflammatory diet (Mediterranean), omega-3s, exercise, quality sleep, reduce visceral fat. Retest if acutely elevated — infections and injuries spike it temporarily."
        ),
        "crp": BiomarkerInfo(
            name: "CRP", system: .inflammation, unit: "mg/L", refMin: 0, refMax: 3.0,
            description: "C-reactive protein — a marker of systemic inflammation produced by the liver.",
            whyItMatters: "Elevated CRP indicates acute or chronic inflammation, which drives many diseases including cardiovascular disease.",
            ifOutOfRange: "Anti-inflammatory diet, omega-3s, reduce stress, improve sleep. Retest when not acutely ill."
        ),
        // MARK: Vitamins & Minerals
        "vitamin d": BiomarkerInfo(
            name: "Vitamin D", system: .vitamins, unit: "ng/mL", refMin: 30, refMax: 100,
            description: "A fat-soluble vitamin (actually a hormone) essential for bone health, immune function, mood, and muscle function.",
            whyItMatters: "Deficiency is extremely common (especially in northern latitudes) and linked to fatigue, depression, weak bones, and increased infection risk. Optimal is 40–60 ng/mL.",
            ifOutOfRange: "Supplement with D3 (2,000–5,000 IU daily with fat), get midday sun exposure, eat fatty fish. Retest after 3 months of supplementation."
        ),
        "vitamin b12": BiomarkerInfo(
            name: "Vitamin B12", system: .vitamins, unit: "pg/mL", refMin: 200, refMax: 1100,
            description: "Essential for nerve function, DNA synthesis, and red blood cell production. Stored in the liver for years.",
            whyItMatters: "Deficiency causes fatigue, brain fog, numbness/tingling, and megaloblastic anemia. Common in vegans, elderly, and those on metformin or PPIs.",
            ifOutOfRange: "Supplement with methylcobalamin or hydroxocobalamin. If severely low, injections may be needed. Optimal is above 500 pg/mL."
        ),
        "folate": BiomarkerInfo(
            name: "Folate", system: .vitamins, unit: "ng/mL", refMin: 5.4, refMax: 40,
            description: "A B vitamin (B9) essential for DNA synthesis, cell division, and red blood cell production.",
            whyItMatters: "Deficiency causes megaloblastic anemia (same as B12 deficiency) and is critical during pregnancy to prevent neural tube defects. Also linked to elevated homocysteine.",
            ifOutOfRange: "Eat leafy greens, legumes, and fortified foods. Supplement with methylfolate if needed. Check B12 too — they work together."
        ),
    ]
}
