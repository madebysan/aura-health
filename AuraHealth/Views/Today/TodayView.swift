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

    private var hiddenMetrics: Set<String> {
        Set(hiddenMetricsRaw.split(separator: ",").map(String.init))
    }

    private var visibleMetrics: [MetricType] {
        MetricType.allCases.filter { !hiddenMetrics.contains($0.rawValue) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Range picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(VitalsRange.allCases) { range in
                            FilterPill(label: range.rawValue, isActive: selectedRange == range) {
                                withAnimation(AppAnimation.viewSwitch) {
                                    selectedRange = range
                                }
                            }
                        }
                    }
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showCardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Choose which cards to show")
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

    private var activeInsights: [SuggestedStep] {
        generateSuggestedSteps().filter { !dismissedInsights.contains($0.message) }
    }

    private var todayContent: some View {
        VStack(spacing: 16) {
            // Date header
            HStack {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 1. Daily Health Score — full width hero
            HealthScoreHeroCard(
                score: dailyHealthScore,
                recentScores: recentHealthScores,
                contributors: scoreContributors
            )
            .staggeredAppearance(index: 0)

            // 2. Insights — stacked card deck (swipe to dismiss)
            let insights = activeInsights
            if !insights.isEmpty {
                InsightCardStack(insights: insights) { message in
                    withAnimation(AppAnimation.appear) {
                        dismissInsight(message)
                    }
                }
                .staggeredAppearance(index: 1)
            }

            // 3. Vitals grid
            LazyVGrid(columns: gridColumns, spacing: 14) {
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
                    .staggeredAppearance(index: index + insights.count + 2)
                }
            }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 520))], spacing: 14) {
                    ForEach(Array(visibleMetrics.enumerated()), id: \.element) { index, metricType in
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
        [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 14)]
        #else
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        #endif
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

    private var scoreColor: Color {
        AppColors.scoreColor(for: score)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Ring
            HealthScoreRingView(score: score, label: "Health", size: 96)

            // Details
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Health")
                    .font(.headline)

                if score > 0 {
                    Text(scoreLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(scoreColor)

                    // 7-day sparkline
                    if recentScores.count >= 2 {
                        SparklineView(values: recentScores, color: scoreColor)
                            .frame(height: 28)
                            .clipped()
                    }

                    Text(contributors)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.quaternary)
                    Text("Connect a data source to see your score")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .cardStyle(padding: 16, cornerRadius: 14)
        .hoverCard()
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

// MARK: - Insight Card Stack (WHOOP-style)

struct InsightCardStack: View {
    let insights: [SuggestedStep]
    let onDismiss: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background cards (show actual content)
            ForEach(Array(insights.enumerated().reversed()), id: \.element.message) { index, step in
                if index > 0 && index <= 2 {
                    InsightCard(step: step, interactive: false) {}
                        .offset(y: CGFloat(index) * 4)
                        .scaleEffect(1.0 - CGFloat(index) * 0.03, anchor: .top)
                        .opacity(1.0 - Double(index) * 0.25)
                        .allowsHitTesting(false)
                }
            }

            // Top card (interactive)
            if let topInsight = insights.first {
                InsightCard(step: topInsight) {
                    onDismiss(topInsight.message)
                }
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(topInsight.message)
            }
        }
        .padding(.bottom, min(CGFloat(insights.count - 1), 2) * 4)
    }
}

struct InsightCard: View {
    let step: SuggestedStep
    var interactive: Bool = true
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    private func animateDismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = -400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 6))

            Text(step.message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if interactive {
                Button {
                    animateDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .offset(x: interactive ? dragOffset : 0)
        .opacity(interactive ? 1.0 - Double(abs(dragOffset)) / 300.0 : 1.0)
        .gesture(
            DragGesture(minimumDistance: interactive ? 10 : .infinity)
                .onChanged { value in
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width < -100 {
                        animateDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
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

// MARK: - Card Settings Sheet

struct VitalsCardSettingsSheet: View {
    @Binding var hiddenMetricsRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hiddenMetrics: Set<String> {
        Set(hiddenMetricsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            List {
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
                                    .foregroundStyle(metricType.iconColor)
                            }
                        }
                    }
                } header: {
                    Text("Choose which metric cards appear on the Vitals dashboard.")
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
