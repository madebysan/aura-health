import Foundation
#if os(macOS)
import PDFKit
#endif

/// Extracts biomarkers from lab report files using local text parsing (no API needed)
enum LocalLabParser {

    // MARK: - Public

    static func parse(fileURL: URL) throws -> [ExtractedBiomarker] {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let text: String
        let isPDF = fileURL.pathExtension.lowercased() == "pdf"

        if isPDF {
            text = try extractTextFromPDF(fileURL)
        } else {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        }

        guard !text.isEmpty else { return [] }

        let lab = detectLab(from: text)
        let testDate = detectDate(from: text, fileName: fileURL.lastPathComponent)

        return extractBiomarkers(from: text, lab: lab, testDate: testDate)
    }

    // MARK: - PDF Text Extraction

    private static func extractTextFromPDF(_ url: URL) throws -> String {
        #if os(macOS)
        guard let document = PDFDocument(url: url) else {
            throw LabParserError.cannotReadPDF
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
        #else
        throw LabParserError.cannotReadPDF
        #endif
    }

    // MARK: - Lab Detection

    private static func detectLab(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("quest diagnostics") || lower.contains("myquest") { return "Quest" }
        if lower.contains("labcorp") { return "LabCorp" }
        if lower.contains("maximus") || lower.contains("maximustribe") { return "Maximus" }
        if lower.contains("crl king") || lower.contains("clinical reference") { return "CRL" }
        return "Lab"
    }

    // MARK: - Date Detection

    private static func detectDate(from text: String, fileName: String) -> String {
        // Try "Collected Date: MM/DD/YYYY"
        if let match = text.range(of: #"Collected Date:\s*(\d{2}/\d{2}/\d{4})"#, options: .regularExpression) {
            let dateStr = String(text[match]).replacingOccurrences(of: "Collected Date:", with: "").trimmingCharacters(in: .whitespaces)
            if let parsed = parseUSDate(dateStr) { return parsed }
        }

        // Try "Date Collected: MM/DD/YYYY"
        if let match = text.range(of: #"Date Collected:\s*(\d{2}/\d{2}/\d{4})"#, options: .regularExpression) {
            let dateStr = String(text[match]).replacingOccurrences(of: "Date Collected:", with: "").trimmingCharacters(in: .whitespaces)
            if let parsed = parseUSDate(dateStr) { return parsed }
        }

        // Try "Sample Collection: Mon DD, YYYY" or "Mar 05, 2026"
        if let match = text.range(of: #"Sample Collection:\s*(\w+ \d{2}, \d{4})"#, options: .regularExpression) {
            let dateStr = String(text[match]).replacingOccurrences(of: "Sample Collection:", with: "").trimmingCharacters(in: .whitespaces)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM dd, yyyy"
            if let d = formatter.date(from: dateStr) {
                let out = DateFormatter()
                out.dateFormat = "yyyy-MM-dd"
                return out.string(from: d)
            }
        }

        // Try filename patterns like "1-19-2026" or "2026-03-05"
        if let match = fileName.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(fileName[match])
        }
        if let match = fileName.range(of: #"(\d{1,2})-(\d{1,2})-(\d{4})"#, options: .regularExpression) {
            let parts = String(fileName[match]).split(separator: "-")
            if parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) {
                return String(format: "%04d-%02d-%02d", y, m, d)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func parseUSDate(_ str: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        guard let date = formatter.date(from: str) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    // MARK: - Biomarker Extraction

    private static func extractBiomarkers(from text: String, lab: String, testDate: String) -> [ExtractedBiomarker] {
        var results: [ExtractedBiomarker] = []

        // Known biomarkers and their patterns
        let markers = knownMarkers()

        let lines = text.components(separatedBy: .newlines)

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for marker in markers {
                guard matchesMarkerName(trimmed, marker: marker) else { continue }

                // Try to extract value from this line or the next few lines
                if let extracted = extractValue(from: lines, startingAt: i, marker: marker, lab: lab, testDate: testDate) {
                    // Avoid duplicates
                    if !results.contains(where: { $0.marker == extracted.marker }) {
                        results.append(extracted)
                    }
                    break
                }
            }
        }

        return results
    }

    private static func matchesMarkerName(_ line: String, marker: MarkerPattern) -> Bool {
        let lower = line.lowercased()
        for name in marker.names {
            if lower.hasPrefix(name.lowercased()) || lower.contains("\t\(name.lowercased())") {
                return true
            }
        }
        return false
    }

    private static func extractValue(from lines: [String], startingAt index: Int, marker: MarkerPattern, lab: String, testDate: String) -> ExtractedBiomarker? {
        // Look at the current line and next 2 lines for a numeric value
        for offset in 0...min(2, lines.count - index - 1) {
            let line = lines[index + offset]

            // Extract numbers from the line
            let numbers = extractNumbers(from: line)

            // Find the result value — typically the first standalone number that isn't part of a range
            for number in numbers {
                // Skip very large numbers (likely not biomarker values)
                if number > 100000 { continue }
                // Skip numbers that look like dates
                if number > 1900 && number < 2100 && number == number.rounded() { continue }

                // Try to find reference range on the same line or nearby
                let refRange = extractRefRange(from: lines, near: index, marker: marker)

                return ExtractedBiomarker(
                    marker: marker.standardName,
                    value: number,
                    unit: marker.unit,
                    refMin: refRange?.min ?? marker.defaultRefMin,
                    refMax: refRange?.max ?? marker.defaultRefMax,
                    lab: lab,
                    testDate: testDate
                )
            }
        }
        return nil
    }

    private static func extractNumbers(from line: String) -> [Double] {
        // Match standalone numbers (including decimals), excluding those inside ranges like "3.4-10.8"
        let pattern = #"(?<![0-9.-])(\d+\.?\d*)(?![0-9]*[-–])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        return matches.compactMap { match in
            let str = nsLine.substring(with: match.range(at: 1))
            return Double(str)
        }
    }

    private static func extractRefRange(from lines: [String], near index: Int, marker: MarkerPattern) -> (min: Double, max: Double)? {
        // Look at the line and nearby lines for range patterns
        for offset in 0...min(3, lines.count - index - 1) {
            let line = lines[index + offset]

            // Pattern: "3.4-10.8" or "0.76 - 1.27" or "3.4–10.8"
            let rangePattern = #"(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)"#
            if let regex = try? NSRegularExpression(pattern: rangePattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let nsLine = line as NSString
                if let min = Double(nsLine.substring(with: match.range(at: 1))),
                   let max = Double(nsLine.substring(with: match.range(at: 2))) {
                    // Sanity check — min should be less than max
                    if min < max && max < 100000 {
                        return (min, max)
                    }
                }
            }

            // Pattern: ">59" or "< 100" or ">= 60"
            let gtPattern = #"[>≥]\s*=?\s*(\d+\.?\d*)"#
            if let regex = try? NSRegularExpression(pattern: gtPattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                if let val = Double((line as NSString).substring(with: match.range(at: 1))) {
                    return (val, val * 2)
                }
            }

            // Pattern: "<200" or "< 100"
            let ltPattern = #"<\s*=?\s*(\d+\.?\d*)"#
            if let regex = try? NSRegularExpression(pattern: ltPattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                if let val = Double((line as NSString).substring(with: match.range(at: 1))) {
                    return (0, val)
                }
            }
        }

        return nil
    }

    // MARK: - Known Markers

    struct MarkerPattern {
        let standardName: String
        let names: [String]
        let unit: String
        let defaultRefMin: Double?
        let defaultRefMax: Double?
    }

    private static func knownMarkers() -> [MarkerPattern] {
        [
            // Lipids
            MarkerPattern(standardName: "Total Cholesterol", names: ["Cholesterol, Total", "Cholesterol Total", "Total Cholesterol"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 200),
            MarkerPattern(standardName: "LDL Cholesterol", names: ["LDL Cholesterol", "LDL Chol", "LDL-C"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 100),
            MarkerPattern(standardName: "HDL Cholesterol", names: ["HDL Cholesterol", "HDL-C"], unit: "mg/dL", defaultRefMin: 40, defaultRefMax: 100),
            MarkerPattern(standardName: "Triglycerides", names: ["Triglycerides"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 150),
            MarkerPattern(standardName: "Non-HDL Cholesterol", names: ["Non HDL Cholesterol", "Non-HDL"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 130),
            MarkerPattern(standardName: "Apolipoprotein B", names: ["Apolipoprotein B", "APOLIPOPROTEIN B", "ApoB"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 90),

            // Inflammation
            MarkerPattern(standardName: "hs-CRP", names: ["hs-CRP", "CRP", "C-Reactive"], unit: "mg/L", defaultRefMin: 0, defaultRefMax: 1.0),

            // Metabolic
            MarkerPattern(standardName: "HbA1c", names: ["Hemoglobin A1c", "HbA1c", "A1C"], unit: "%", defaultRefMin: 0, defaultRefMax: 5.7),
            MarkerPattern(standardName: "Glucose", names: ["Glucose", "Glucose (Blood Sugar)"], unit: "mg/dL", defaultRefMin: 65, defaultRefMax: 99),
            MarkerPattern(standardName: "Insulin", names: ["INSULIN", "Insulin"], unit: "uIU/mL", defaultRefMin: 0, defaultRefMax: 18.4),

            // Kidney
            MarkerPattern(standardName: "Creatinine", names: ["Creatinine"], unit: "mg/dL", defaultRefMin: 0.60, defaultRefMax: 1.27),
            MarkerPattern(standardName: "eGFR", names: ["eGFR", "EGFR"], unit: "mL/min/1.73m2", defaultRefMin: 60, defaultRefMax: 120),
            MarkerPattern(standardName: "BUN", names: ["BUN", "Urea Nitrogen"], unit: "mg/dL", defaultRefMin: 6, defaultRefMax: 25),
            MarkerPattern(standardName: "Cystatin C", names: ["Cystatin C"], unit: "mg/L", defaultRefMin: 0.60, defaultRefMax: 1.00),

            // Liver
            MarkerPattern(standardName: "AST", names: ["AST", "Aspartate Aminotransferase", "AST (SGOT)"], unit: "U/L", defaultRefMin: 0, defaultRefMax: 40),
            MarkerPattern(standardName: "ALT", names: ["ALT", "Alanine Aminotransferase", "ALT (SGPT)"], unit: "U/L", defaultRefMin: 0, defaultRefMax: 44),
            MarkerPattern(standardName: "Alkaline Phosphatase", names: ["Alkaline Phosphatase"], unit: "U/L", defaultRefMin: 36, defaultRefMax: 130),
            MarkerPattern(standardName: "Bilirubin, Total", names: ["Bilirubin, Total", "Bilirubin Total", "Total Bilirubin"], unit: "mg/dL", defaultRefMin: 0, defaultRefMax: 1.2),
            MarkerPattern(standardName: "Albumin", names: ["Albumin"], unit: "g/dL", defaultRefMin: 3.6, defaultRefMax: 5.1),
            MarkerPattern(standardName: "Protein, Total", names: ["Protein, Total", "Total Protein"], unit: "g/dL", defaultRefMin: 6.0, defaultRefMax: 8.5),
            MarkerPattern(standardName: "Globulin", names: ["Globulin, Total", "Globulin"], unit: "g/dL", defaultRefMin: 1.5, defaultRefMax: 4.5),

            // Thyroid
            MarkerPattern(standardName: "TSH", names: ["TSH", "TSH (Thyroid"], unit: "mIU/L", defaultRefMin: 0.40, defaultRefMax: 4.50),
            MarkerPattern(standardName: "Free T4", names: ["T4, FREE", "Free T4", "Free Thyroxine", "Thyroxine (T4)"], unit: "ng/dL", defaultRefMin: 0.8, defaultRefMax: 1.8),
            MarkerPattern(standardName: "Free T3", names: ["T3, FREE", "Free T3"], unit: "pg/mL", defaultRefMin: 2.3, defaultRefMax: 4.2),

            // CBC
            MarkerPattern(standardName: "WBC", names: ["WBC", "White Blood Cell Count"], unit: "x10E3/uL", defaultRefMin: 3.4, defaultRefMax: 10.8),
            MarkerPattern(standardName: "RBC", names: ["RBC", "Red Blood Cell Count"], unit: "x10E6/uL", defaultRefMin: 4.14, defaultRefMax: 5.80),
            MarkerPattern(standardName: "Hemoglobin", names: ["Hemoglobin"], unit: "g/dL", defaultRefMin: 13.0, defaultRefMax: 17.7),
            MarkerPattern(standardName: "Hematocrit", names: ["Hematocrit"], unit: "%", defaultRefMin: 37.5, defaultRefMax: 51.0),
            MarkerPattern(standardName: "MCV", names: ["MCV", "Mean RBC Volume"], unit: "fL", defaultRefMin: 79, defaultRefMax: 97),
            MarkerPattern(standardName: "MCH", names: ["MCH", "Mean RBC Iron"], unit: "pg", defaultRefMin: 26.6, defaultRefMax: 33.0),
            MarkerPattern(standardName: "MCHC", names: ["MCHC", "Mean RBC Iron Concentration"], unit: "g/dL", defaultRefMin: 31.5, defaultRefMax: 35.7),
            MarkerPattern(standardName: "RDW", names: ["RDW", "RBC Distribution Width"], unit: "%", defaultRefMin: 11.0, defaultRefMax: 15.4),
            MarkerPattern(standardName: "Platelets", names: ["Platelets"], unit: "x10E3/uL", defaultRefMin: 140, defaultRefMax: 450),

            // Electrolytes
            MarkerPattern(standardName: "Sodium", names: ["Sodium"], unit: "mmol/L", defaultRefMin: 134, defaultRefMax: 146),
            MarkerPattern(standardName: "Potassium", names: ["Potassium"], unit: "mmol/L", defaultRefMin: 3.5, defaultRefMax: 5.3),
            MarkerPattern(standardName: "Chloride", names: ["Chloride"], unit: "mmol/L", defaultRefMin: 96, defaultRefMax: 110),
            MarkerPattern(standardName: "Carbon Dioxide", names: ["Carbon Dioxide", "CO2, Total"], unit: "mmol/L", defaultRefMin: 20, defaultRefMax: 32),
            MarkerPattern(standardName: "Calcium", names: ["Calcium"], unit: "mg/dL", defaultRefMin: 8.6, defaultRefMax: 10.3),

            // Vitamins
            MarkerPattern(standardName: "Vitamin D", names: ["Vitamin D", "25-OH Vitamin D"], unit: "ng/mL", defaultRefMin: 30, defaultRefMax: 100),
            MarkerPattern(standardName: "Vitamin B12", names: ["VITAMIN B12", "Vitamin B12", "B12"], unit: "pg/mL", defaultRefMin: 200, defaultRefMax: 1100),
            MarkerPattern(standardName: "Folate", names: ["FOLATE", "Folate", "Folic Acid"], unit: "ng/mL", defaultRefMin: 5.4, defaultRefMax: 40),

            // Hormones
            MarkerPattern(standardName: "Testosterone, Total", names: ["TESTOSTERONE, TOTAL", "Testosterone, Total", "Total Testosterone"], unit: "ng/dL", defaultRefMin: 250, defaultRefMax: 1100),
            MarkerPattern(standardName: "Free Testosterone", names: ["Free Testosterone"], unit: "pg/mL", defaultRefMin: 0.1, defaultRefMax: 190),
            MarkerPattern(standardName: "Estradiol", names: ["Estradiol"], unit: "pg/mL", defaultRefMin: 11.3, defaultRefMax: 43.0),
            MarkerPattern(standardName: "LH", names: ["Luteinizing Hormone", "LH"], unit: "IU/L", defaultRefMin: 1.7, defaultRefMax: 8.6),
            MarkerPattern(standardName: "FSH", names: ["Follicle Stimulating Hormone", "FSH"], unit: "IU/L", defaultRefMin: 1.5, defaultRefMax: 12.4),
            MarkerPattern(standardName: "SHBG", names: ["Sex Hormone Binding", "SHBG"], unit: "nmol/L", defaultRefMin: 16.5, defaultRefMax: 76.0),
            MarkerPattern(standardName: "PSA", names: ["Prostate-Specific Antigen", "PSA"], unit: "ng/mL", defaultRefMin: 0, defaultRefMax: 4.0),
            MarkerPattern(standardName: "Ferritin", names: ["Ferritin"], unit: "ng/mL", defaultRefMin: 38, defaultRefMax: 380),
        ]
    }
}

enum LabParserError: LocalizedError {
    case cannotReadPDF

    var errorDescription: String? {
        switch self {
        case .cannotReadPDF: "Could not read PDF file."
        }
    }
}
