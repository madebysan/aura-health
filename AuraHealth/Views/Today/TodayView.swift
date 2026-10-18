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
    @State private var showCardSettings = false
    @AppStorage("hiddenMetrics") private var hiddenMetricsRaw: String = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hiddenMetrics: Set<String> {
        Set(hiddenMetricsRaw.split(separator: ",").map(String.init))
    }

    private var visibleMetrics: [MetricType] {
        MetricType.allCases.filter { !hiddenMetrics.contains($0.rawValue) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .kicker()
                    .padding(.bottom, 10)

                // Range picker
                UnderlineTabs(options: VitalsRange.allCases, selection: $selectedRange) { $0.rawValue }

                if selectedRange == .today {
                    todayContent
                } else {
                    trendsContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Vitals")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showCardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Choose which cards to show")
                .accessibilityLabel("Choose Visible Vital Cards")
            }
        }
        #if os(macOS)
        .frame(minWidth: 600)
        #endif
        .sheet(isPresented: $showCardSettings) {
            VitalsCardSettingsSheet(hiddenMetricsRaw: $hiddenMetricsRaw)
        }
        .sheet(item: $selectedMetricType) { metricType in
            AddMeasurementSheet(metricType: metricType)
        }
        .sheet(item: $detailMetricType) { metricType in
            MetricDetailSheet(metricType: metricType)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addMeasurement)) { _ in
            selectedMetricType = .weight
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMetricDetail)) { notification in
            if let metric = notification.object as? MetricType {
                detailMetricType = metric
            }
        }
    }

    // MARK: - Today Content (card grid)

    @AppStorage("dismissedInsights") private var dismissedInsightsRaw: String = ""

    private var dismissedInsights: Set<String> {
        Set(dismissedInsightsRaw.split(separator: "|").map(String.init))
    }

    private func dismissInsight(_ message: String) {
        var dismissed = dismissedInsights
        dismissed.insert(message)
        dismissedInsightsRaw = dismissed.joined(separator: "|")
    }

    @State private var showAllNotes = false

    private func noteTag(_ step: SuggestedStep) -> String {
        switch step.type {
        case .warning: "Flag"
        case .suggestion: "Tip"
        case .info: "Note"
        }
    }

    private func noteColor(_ step: SuggestedStep) -> Color {
        step.type == .warning ? Notebook.signal : Notebook.inkSecondary
    }

    private var activeInsights: [SuggestedStep] {
        generateSuggestedSteps().filter { !dismissedInsights.contains($0.message) }
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Daily Health summary
            HealthScoreHeroCard(
                score: dailyHealthScore,
                recentScores: recentHealthScores,
                contributors: scoreContributors
            )
            .staggeredAppearance(index: 0)

            // 2. Notes: every note is visible as its own line with its own Dismiss.
            // With several, a "Notes" header shows the count; beyond three they fold.
            let insights = activeInsights
            if insights.count > 1 {
                NotebookSectionHeader(title: "Notes", trailing: "\(insights.count)")
                    .staggeredAppearance(index: 1)
            }
            let shown = showAllNotes ? insights : Array(insights.prefix(3))
            ForEach(shown, id: \.message) { step in
                NoteLine(text: step.message, tag: noteTag(step), tagColor: noteColor(step)) {
                    withAnimation(AppAnimation.collapse) {
                        dismissInsight(step.message)
                    }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
            }
            if insights.count > 3 {
                Button(showAllNotes ? "Show fewer notes" : "Show \(insights.count - 3) more") {
                    withAnimation(AppAnimation.expand) { showAllNotes.toggle() }
                }
                .font(Notebook.mono(.caption))
                .underline()
                .foregroundStyle(Notebook.inkSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }

            // 3. Vitals table
            HStack {
                Text("Measure")
                Spacer()
                Text("Latest")
                    .frame(alignment: .trailing)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Trend").frame(width: 64, alignment: .leading)
                }
            }
            .kicker(Notebook.inkTertiary)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            ForEach(Array(todayVisibleMetrics.enumerated()), id: \.element) { index, metricType in
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
                .staggeredAppearance(index: index + 2)
            }
        }
    }

    // MARK: - Trends Content (charts for selected range)

    private var trendsContent: some View {
        VStack(spacing: 0) {
            let filtered = filteredMeasurements()
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "chart.xyaxis.line",
                    title: "No Data Yet",
                    message: "Start logging measurements from the Today view to see trends here.",
                    chatHint: "Try \"Log my weight as 75kg\" in Chat"
                )
                .padding(.top, 40)
            } else {
                let sortedMetrics = visibleMetrics.sorted { a, b in
                    let aHasData = !filteredMeasurements(for: a).isEmpty
                    let bHasData = !filteredMeasurements(for: b).isEmpty
                    if aHasData != bHasData { return aHasData }
                    return false
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedMetrics.enumerated()), id: \.element) { index, metricType in
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

    // MARK: - Auto-only Metrics (hide when no data)

    /// Metrics that only arrive from integrations (WHOOP / Apple Health) and aren't manually addable.
    /// Hidden from the Today grid when there's no data for them.
    private static let autoOnlyMetrics: Set<MetricType> = [.activeMinutes, .recovery, .strain, .sleepScore]

    private var todayVisibleMetrics: [MetricType] {
        let filtered = visibleMetrics.filter { metric in
            if Self.autoOnlyMetrics.contains(metric) {
                return latestMeasurement(for: metric) != nil
            }
            return true
        }
        // Sort: metrics with data first, then metrics without data
        return filtered.sorted { a, b in
            let aHasData = latestMeasurement(for: a) != nil
            let bHasData = latestMeasurement(for: b) != nil
            if aHasData != bHasData { return aHasData }
            return false
        }
    }

    // MARK: - Data Helpers (cached by type)

    /// Measurements grouped by MetricType — computed once and reused
    private var measurementsByType: [MetricType: [Measurement]] {
        Dictionary(grouping: allMeasurements, by: \.metricType)
    }

    private func latestMeasurement(for type: MetricType) -> Measurement? {
        measurementsByType[type]?.first
    }

    private func previousMeasurement(for type: MetricType) -> Measurement? {
        guard let matching = measurementsByType[type], matching.count > 1 else { return nil }
        return matching[1]
    }

    private func latestValue(for type: MetricType) -> Double? {
        latestMeasurement(for: type)?.value
    }

    private func recentValues(for type: MetricType, days: Int) -> [Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        guard let matching = measurementsByType[type] else { return [] }
        return matching
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.value)
    }

    private var recentHealthScores: [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Pre-group measurements by day for score calculation
        let recentCutoff = cal.date(byAdding: .day, value: -7, to: today)!
        let recentMeasurements = allMeasurements.filter { $0.timestamp >= recentCutoff }
        let byDay = Dictionary(grouping: recentMeasurements) { cal.startOfDay(for: $0.timestamp) }

        return (0..<7).reversed().compactMap { daysAgo -> Double? in
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let dayMeasurements = byDay[date] ?? []
            return computeHealthScore(from: dayMeasurements)
        }.filter { $0 > 0 }
    }

    /// Each contributing metric has a weight and a normalizer that maps its value to 0–100.
    private static let scoreComponents: [(type: MetricType, weight: Double, normalize: (Double) -> Double)] = [
        // WHOOP-specific (highest signal when available)
        (.recovery, 0.30, { min($0, 100) }),
        (.sleepScore, 0.25, { min($0, 100) }),
        // Available from Apple Health + WHOOP
        (.hrv, 0.15, { min(max(($0 - 20) / 80 * 100, 0), 100) }),
        (.heartRate, 0.10, { v in
            // Resting HR: lower is better. 40-100 range → 100-0 score
            min(max((100 - v) / 60 * 100, 0), 100)
        }),
        (.sleepDuration, 0.10, { v in
            // 7-9h is optimal (100), <5h or >11h scores low
            if v >= 7 && v <= 9 { return 100 }
            if v >= 6 && v < 7 { return 70 }
            if v >= 9 && v <= 10 { return 80 }
            if v >= 5 && v < 6 { return 40 }
            return 20
        }),
        (.steps, 0.05, { min($0 / 10000 * 100, 100) }),
        (.activeMinutes, 0.03, { min($0 / 60 * 100, 100) }),
        (.spo2, 0.02, { v in
            // 95-100% is healthy
            if v >= 95 { return 100 }
            if v >= 90 { return 60 }
            return 20
        }),
    ]

    private func computeHealthScore(from measurements: [Measurement]) -> Double {
        var total: Double = 0
        var totalWeight: Double = 0

        for component in Self.scoreComponents {
            if let value = measurements.first(where: { $0.metricType == component.type })?.value {
                total += component.normalize(value) * component.weight
                totalWeight += component.weight
            }
        }

        guard totalWeight > 0 else { return 0 }
        return total / totalWeight
    }

    private var dailyHealthScore: Double {
        var total: Double = 0
        var totalWeight: Double = 0

        for component in Self.scoreComponents {
            if let value = latestValue(for: component.type) {
                total += component.normalize(value) * component.weight
                totalWeight += component.weight
            }
        }

        guard totalWeight > 0 else { return 0 }
        return total / totalWeight
    }

    /// Human-readable summary of which metrics contribute to the score
    private var scoreContributors: String {
        let available = Self.scoreComponents.compactMap { component -> String? in
            guard latestValue(for: component.type) != nil else { return nil }
            return component.type.displayName.lowercased()
        }
        guard !available.isEmpty else { return "No data yet" }
        return "Based on \(available.joined(separator: ", "))"
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

// MARK: - Health Score Hero Card (full width)

struct HealthScoreHeroCard: View {
    let score: Double
    let recentScores: [Double]
    var contributors: String = "No data yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily health").kicker()

            if score > 0 {
                HStack(alignment: .firstTextBaseline) {
                    BigNumber(value: "\(Int(score))", suffix: "/100")
                    Spacer()
                    Text(scoreLabel).kicker()
                }

                // Last 7 days, today solid
                if recentScores.count >= 2 {
                    BarSparkline(values: recentScores, floor: 40)
                        .frame(height: 22)
                        .padding(.top, 4)
                        .accessibilityLabel("Daily health, last 7 days")
                        .accessibilityValue(ChartSummary.direction(from: recentScores.first ?? 0, to: recentScores.last ?? 0))
                }

                Text(contributors)
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
                    .padding(.top, 4)
            } else {
                Text("No data yet")
                    .font(Notebook.mono(.title3))
                    .foregroundStyle(Notebook.inkSecondary)
                Text("Connect Apple Health or add a measurement to see your score.")
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score > 0 ? "Daily health \(Int(score)) out of 100, \(scoreLabel)" : "Daily health, no data yet")
    }

    private var scoreLabel: String {
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Low"
    }
}

// MARK: - Insight Card (individual, dismissible)

struct SuggestedStep {
    enum StepType { case warning, suggestion, info }
    let type: StepType
    let message: String
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
            NotebookForm {
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

// MARK: - Card Settings Sheet

struct VitalsCardSettingsSheet: View {
    @Binding var hiddenMetricsRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hiddenMetrics: Set<String> {
        Set(hiddenMetricsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            NotebookForm {
                Section {
                    ForEach(MetricType.allCases) { metricType in
                        let isVisible = !hiddenMetrics.contains(metricType.rawValue)
                        Toggle(isOn: Binding(
                            get: { isVisible },
                            set: { newValue in
                                var set = hiddenMetrics
                                if newValue {
                                    set.remove(metricType.rawValue)
                                } else {
                                    set.insert(metricType.rawValue)
                                }
                                hiddenMetricsRaw = set.sorted().joined(separator: ",")
                            }
                        )) {
                            Label {
                                Text(metricType.displayName)
                            } icon: {
                                Image(systemName: metricType.iconName)
                                    .foregroundStyle(Notebook.ink)
                            }
                        }
                    }
                } header: {
                    Text("Choose which measures appear on Vitals.")
                        .font(.footnote)
                        .foregroundStyle(Notebook.inkSecondary)
                        .textCase(nil)
                }
            }
            .navigationTitle("Visible Cards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

#Preview {
    NavigationStack {
        VitalsView()
    }
    .modelContainer(for: [Measurement.self, Medication.self, MedicationLog.self, Habit.self, HabitLog.self, Biomarker.self, Condition.self, DietPlan.self, MetricRange.self, VaultDocument.self, HealthMemory.self, Conversation.self], inMemory: true)
}
