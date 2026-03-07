import SwiftUI
import SwiftData
import Charts

// MARK: - Vitals Range

enum VitalsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .today: 1
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

// MARK: - Vitals View

struct VitalsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Measurement.timestamp, order: .reverse)
    private var allMeasurements: [Measurement]

    @Query(filter: #Predicate<Medication> { $0.active })
    private var activeMedications: [Medication]

    @Query(filter: #Predicate<Habit> { $0.active })
    private var activeHabits: [Habit]

    @State private var selectedRange: VitalsRange = .today
    @State private var selectedMetricType: MetricType?
    @State private var detailMetricType: MetricType?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Range picker
                HStack(spacing: 6) {
                    ForEach(VitalsRange.allCases) { range in
                        FilterPill(label: range.rawValue, isActive: selectedRange == range) {
                            withAnimation(AppAnimation.viewSwitch) {
                                selectedRange = range
                            }
                        }
                    }
                    Spacer()
                }

                if selectedRange == .today {
                    todayContent
                } else {
                    trendsContent
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Vitals")
        #if os(macOS)
        .frame(minWidth: 600)
        #endif
        .sheet(item: $selectedMetricType) { metricType in
            AddMeasurementSheet(metricType: metricType)
        }
        .sheet(item: $detailMetricType) { metricType in
            MetricDetailSheet(metricType: metricType)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addMeasurement)) { _ in
            selectedMetricType = .weight
        }
    }

    // MARK: - Today Content (card grid)

    private var todayContent: some View {
        VStack(spacing: 24) {
            // Date header
            HStack {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Metrics grid
            LazyVGrid(columns: gridColumns, spacing: 10) {
                HealthScoreCard(
                    score: dailyHealthScore,
                    recentScores: recentHealthScores
                )
                .staggeredAppearance(index: 0)

                ForEach(Array(MetricType.allCases.enumerated()), id: \.element) { index, metricType in
                    MetricCardView(
                        metricType: metricType,
                        latest: latestMeasurement(for: metricType),
                        previous: previousMeasurement(for: metricType),
                        recentValues: recentValues(for: metricType, days: 7),
                        onAdd: {
                            if latestMeasurement(for: metricType) != nil {
                                detailMetricType = metricType
                            } else {
                                selectedMetricType = metricType
                            }
                        }
                    )
                    .contextMenu {
                        Button {
                            selectedMetricType = metricType
                        } label: {
                            Label("Add Measurement", systemImage: "plus")
                        }
                    }
                    .staggeredAppearance(index: index + 1)
                }
            }

            // Insights
            suggestedStepsSection
        }
    }

    // MARK: - Trends Content (charts for selected range)

    private var trendsContent: some View {
        VStack(spacing: 14) {
            let filtered = filteredMeasurements()
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "chart.xyaxis.line",
                    title: "No Data Yet",
                    message: "Start logging measurements from the Today view to see trends here."
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520))], spacing: 14) {
                    ForEach(Array(MetricType.allCases.enumerated()), id: \.element) { index, metricType in
                        let data = filteredMeasurements(for: metricType)
                        if !data.isEmpty {
                            TrendChartCard(metricType: metricType, measurements: data)
                                .staggeredAppearance(index: index)
                        }
                    }
                }
            }
        }
    }

    private func filteredMeasurements(for type: MetricType? = nil) -> [Measurement] {
        allMeasurements.filter { m in
            let typeMatch = type == nil || m.metricType == type
            let dateMatch: Bool
            if let start = selectedRange.startDate {
                dateMatch = m.timestamp >= start
            } else {
                dateMatch = true
            }
            return typeMatch && dateMatch
        }
    }

    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 10)]
        #else
        [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 10)]
        #endif
    }

    // MARK: - Suggested Steps

    @ViewBuilder
    private var suggestedStepsSection: some View {
        let steps = generateSuggestedSteps()
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Insights")

                ForEach(Array(steps.enumerated()), id: \.element.message) { index, step in
                    SuggestedStepRow(step: step)
                        .staggeredAppearance(index: index + 15)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Data Helpers

    private func latestMeasurement(for type: MetricType) -> Measurement? {
        allMeasurements.first { $0.metricType == type }
    }

    private func previousMeasurement(for type: MetricType) -> Measurement? {
        let matching = allMeasurements.filter { $0.metricType == type }
        return matching.count > 1 ? matching[1] : nil
    }

    private func latestValue(for type: MetricType) -> Double? {
        latestMeasurement(for: type)?.value
    }

    private func recentValues(for type: MetricType, days: Int) -> [Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return allMeasurements
            .filter { $0.metricType == type && $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.value)
    }

    private var recentHealthScores: [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { daysAgo -> Double? in
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let nextDay = cal.date(byAdding: .day, value: 1, to: date)!
            let dayMeasurements = allMeasurements.filter { $0.timestamp >= date && $0.timestamp < nextDay }
            return computeHealthScore(from: dayMeasurements)
        }.filter { $0 > 0 }
    }

    private func computeHealthScore(from measurements: [Measurement]) -> Double {
        var total: Double = 0
        var totalWeight: Double = 0

        if let recovery = measurements.first(where: { $0.metricType == .recovery })?.value {
            total += min(recovery, 100) * 0.4
            totalWeight += 0.4
        }
        if let sleepScore = measurements.first(where: { $0.metricType == .sleepScore })?.value {
            total += min(sleepScore, 100) * 0.35
            totalWeight += 0.35
        }
        if let hrv = measurements.first(where: { $0.metricType == .hrv })?.value {
            let normalized = min(max((hrv - 20) / 80 * 100, 0), 100)
            total += normalized * 0.25
            totalWeight += 0.25
        }

        guard totalWeight > 0 else { return 0 }
        return total / totalWeight
    }

    private var dailyHealthScore: Double {
        var total: Double = 0
        var totalWeight: Double = 0

        if let recovery = latestValue(for: .recovery) {
            total += min(recovery, 100) * 0.4
            totalWeight += 0.4
        }
        if let sleepScore = latestValue(for: .sleepScore) {
            total += min(sleepScore, 100) * 0.35
            totalWeight += 0.35
        }
        if let hrv = latestValue(for: .hrv) {
            let normalized = min(max((hrv - 20) / 80 * 100, 0), 100)
            total += normalized * 0.25
            totalWeight += 0.25
        }

        guard totalWeight > 0 else { return 0 }
        return total / totalWeight
    }

    private func generateSuggestedSteps() -> [SuggestedStep] {
        var steps: [SuggestedStep] = []

        for type in MetricType.allCases {
            guard let latest = latestMeasurement(for: type) else { continue }
            let range = type.defaultRange
            if latest.value < range.low || latest.value > range.high {
                steps.append(SuggestedStep(
                    type: .warning,
                    message: "\(type.displayName) is outside your typical range (\(latest.displayValue) \(type.unit))"
                ))
            }
        }

        for type in [MetricType.weight, .bloodPressure, .heartRate] {
            if let latest = latestMeasurement(for: type) {
                let daysSince = Calendar.current.dateComponents([.day], from: latest.timestamp, to: Date()).day ?? 0
                if daysSince > 7 {
                    steps.append(SuggestedStep(
                        type: .suggestion,
                        message: "You haven't logged \(type.displayName) in \(daysSince) days"
                    ))
                }
            } else {
                steps.append(SuggestedStep(
                    type: .suggestion,
                    message: "Start tracking \(type.displayName) for better health insights"
                ))
            }
        }

        return Array(steps.prefix(5))
    }
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let score: Double
    let recentScores: [Double]

    private var scoreColor: Color {
        AppColors.scoreColor(for: score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 20, height: 20)
                    .background(Color.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                Text("Daily Health")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if score > 0 {
                    Circle()
                        .fill(scoreColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: scoreColor.opacity(0.4), radius: 3)
                }
            }

            // Score value
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if score > 0 {
                    Text("\(Int(score))")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())

                    Text("/ 100")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("--")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.quaternary)
                }
            }

            // Score label
            if score > 0 {
                Text(scoreLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(scoreColor)
            } else {
                Text(" ")
                    .font(.caption2)
            }

            // Sparkline
            if recentScores.count >= 2 {
                SparklineView(values: recentScores, color: scoreColor)
                    .frame(height: 30)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 30)
            }

            // Timestamp
            Text("Updated now")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .cardStyle(padding: 14, cornerRadius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .hoverCard()
    }

    private var scoreLabel: String {
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Low"
    }
}

// MARK: - Suggested Step

struct SuggestedStep {
    enum StepType { case warning, suggestion, info }
    let type: StepType
    let message: String
}

struct SuggestedStepRow: View {
    let step: SuggestedStep

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 5))

            Text(step.message)
                .font(.subheadline)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch step.type {
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb.fill"
        case .info: "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch step.type {
        case .warning: .orange
        case .suggestion: .blue
        case .info: .secondary
        }
    }
}

// MARK: - Add Measurement Sheet

struct AddMeasurementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let metricType: MetricType

    @State private var value: String = ""
    @State private var value2: String = ""
    @State private var notes: String = ""
    @State private var timestamp: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(metricType.hasDualValue ? "Systolic" : "Value", text: $value)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif

                        if metricType.hasDualValue {
                            Text("/")
                                .foregroundStyle(.tertiary)
                            TextField("Diastolic", text: $value2)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }

                        Text(metricType.unit)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DatePicker("Date", selection: $timestamp)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add \(metricType.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(value.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    private func save() {
        guard let val = Double(value) else { return }
        let val2 = metricType.hasDualValue ? Double(value2) : nil

        let measurement = Measurement(
            timestamp: timestamp,
            metricType: metricType,
            value: val,
            value2: val2,
            source: .manual,
            notes: notes
        )

        modelContext.insert(measurement)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        VitalsView()
    }
    .modelContainer(for: [Measurement.self, Medication.self, MedicationLog.self, Habit.self, HabitLog.self, Biomarker.self, Condition.self, DietPlan.self, MetricRange.self, VaultDocument.self, HealthMemory.self, Conversation.self], inMemory: true)
}
