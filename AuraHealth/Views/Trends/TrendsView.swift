import SwiftUI
import SwiftData
import Charts

// MARK: - Correlations View

struct CorrelationsView: View {
    @Query(sort: \Measurement.timestamp, order: .reverse)
    private var measurements: [Measurement]

    @State private var selectedRange: TimeRange = .month

    private let correlationPairs: [(MetricType, MetricType, String)] = [
        (.sleepScore, .recovery, "Sleep Score vs Recovery"),
        (.hrv, .strain, "HRV vs Strain"),
        (.sleepDuration, .heartRate, "Sleep Duration vs Resting HR"),
        (.steps, .calories, "Steps vs Calories"),
        (.recovery, .strain, "Recovery vs Strain"),
        (.sleepScore, .hrv, "Sleep Score vs HRV"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Range selector
                UnderlineTabs(options: TimeRange.allCases, selection: $selectedRange) { $0.rawValue }

                let filtered = filteredMeasurements()
                let availablePairs = correlationPairs.filter { pair in
                    filtered.contains { $0.metricType == pair.0 } && filtered.contains { $0.metricType == pair.1 }
                }

                if availablePairs.isEmpty {
                    EmptyStateView(
                        icon: "chart.xyaxis.line",
                        title: "No Correlations Yet",
                        message: "Log measurements for multiple metrics to see how they relate to each other."
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(availablePairs.enumerated()), id: \.element.2) { index, pair in
                            CorrelationCard(
                                title: pair.2,
                                typeA: pair.0,
                                typeB: pair.1,
                                measurements: filtered
                            )
                            .staggeredAppearance(index: index)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Correlations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private func filteredMeasurements() -> [Measurement] {
        measurements.filter { m in
            if let start = selectedRange.startDate {
                return m.timestamp >= start
            }
            return true
        }
    }
}

// MARK: - Trend Chart Card (used by VitalsView)

struct TrendChartCard: View {
    let metricType: MetricType
    let measurements: [Measurement]

    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 22

    private var selectedMeasurement: Measurement? {
        guard let selectedDate else { return nil }
        return sortedData.min(by: {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        })
    }

    private var sortedData: [Measurement] {
        measurements.sorted { $0.timestamp < $1.timestamp }
    }

    private var stats: (avg: Double, min: Double, max: Double) {
        let values = measurements.map(\.value)
        guard !values.isEmpty else { return (0, 0, 0) }
        let avg = values.reduce(0, +) / Double(values.count)
        return (avg, values.min() ?? 0, values.max() ?? 0)
    }

    private var yDomain: ClosedRange<Double> {
        var allValues = measurements.map(\.value)
        allValues.append(contentsOf: measurements.compactMap(\.value2))
        guard let lo = allValues.min(), let hi = allValues.max() else { return 0...100 }
        let padding = max((hi - lo) * 0.15, 5)
        return max(lo - padding, 0)...(hi + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Text(metricType.displayName)
                    .font(.headline)
                    .foregroundStyle(Notebook.ink)

                Spacer()

                Text("\(measurements.count) readings")
                    .kicker()
            }

            // Chart
            Chart(sortedData, id: \.id) { measurement in
                if metricType == .bloodPressure {
                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Systolic", measurement.value)
                    )
                    .foregroundStyle(Notebook.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)

                    if let diastolic = measurement.value2 {
                        LineMark(
                            x: .value("Date", measurement.timestamp),
                            y: .value("Diastolic", diastolic)
                        )
                        .foregroundStyle(Notebook.inkSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .interpolationMethod(.monotone)
                    }
                } else {
                    AreaMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Value", measurement.value)
                    )
                    .foregroundStyle(Notebook.ink.opacity(0.06))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Value", measurement.value)
                    )
                    .foregroundStyle(Notebook.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }

                if let selected = selectedMeasurement {
                    RuleMark(x: .value("Selected", selected.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, spacing: 6) {
                            VStack(spacing: 2) {
                                if metricType == .bloodPressure, let v2 = selected.value2 {
                                    Text("\(selected.displayValue)/\(Int(v2)) \(metricType.unit)")
                                        .font(.caption.weight(.semibold))
                                } else {
                                    Text("\(selected.displayValue) \(metricType.unit)")
                                        .font(.caption.weight(.semibold))
                                }
                                Text(selected.timestamp, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: 160)
            .clipped()
            .accessibilityLabel("\(metricType.displayName) trend")
            .accessibilityValue(ChartSummary.trend(points: sortedData.map { ($0.timestamp, $0.value) }, unit: metricType.unit))

            // Stats
            HStack(spacing: 0) {
                statPill("Avg", value: stats.avg, color: Notebook.ink)
                Spacer()
                statPill("Min", value: stats.min, color: Notebook.inkSecondary)
                Spacer()
                statPill("Max", value: stats.max, color: Notebook.inkSecondary)
            }
        }
        .padding(.vertical, 18)
        .ruled()
    }

    private func statPill(_ label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .kicker(Notebook.inkTertiary)
            Text(value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value))
                .font(Notebook.mono(.callout, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Correlation Card

struct CorrelationCard: View {
    let title: String
    let typeA: MetricType
    let typeB: MetricType
    let measurements: [Measurement]

    private var pairedData: [(a: Double, b: Double)] {
        let cal = Calendar.current
        let byTypeA = Dictionary(grouping: measurements.filter { $0.metricType == typeA }) { cal.startOfDay(for: $0.timestamp) }
        let byTypeB = Dictionary(grouping: measurements.filter { $0.metricType == typeB }) { cal.startOfDay(for: $0.timestamp) }

        var pairs: [(a: Double, b: Double)] = []
        for (day, aItems) in byTypeA {
            if let bItems = byTypeB[day], let a = aItems.first, let b = bItems.first {
                pairs.append((a: a.value, b: b.value))
            }
        }
        return pairs
    }

    private var correlationCoefficient: Double {
        let n = Double(pairedData.count)
        guard n >= 3 else { return 0 }
        let sumA = pairedData.reduce(0.0) { $0 + $1.a }
        let sumB = pairedData.reduce(0.0) { $0 + $1.b }
        let sumAB = pairedData.reduce(0.0) { $0 + $1.a * $1.b }
        let sumA2 = pairedData.reduce(0.0) { $0 + $1.a * $1.a }
        let sumB2 = pairedData.reduce(0.0) { $0 + $1.b * $1.b }
        let num = n * sumAB - sumA * sumB
        let den = sqrt((n * sumA2 - sumA * sumA) * (n * sumB2 - sumB * sumB))
        return den == 0 ? 0 : num / den
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(pairedData.count) days")
                    .kicker()
            }

            if pairedData.count >= 3 {
                HStack {
                    Spacer()
                    let r = correlationCoefficient
                    Text("r = \(String(format: "%.2f", r))")
                        .font(Notebook.mono(.caption, weight: .medium))
                        .foregroundStyle(abs(r) > 0.5 ? Notebook.ink : Notebook.inkSecondary)
                        .accessibilityLabel(ChartSummary.correlation(r))
                }

                Chart(pairedData.indices, id: \.self) { i in
                    PointMark(
                        x: .value(typeA.displayName, pairedData[i].a),
                        y: .value(typeB.displayName, pairedData[i].b)
                    )
                    .foregroundStyle(Notebook.ink.opacity(0.7))
                    .symbol(.square)
                    .symbolSize(24)
                }
                .chartXAxisLabel(typeA.displayName)
                .chartYAxisLabel(typeB.displayName)
                .accessibilityLabel("\(typeA.displayName) against \(typeB.displayName)")
                .accessibilityValue("\(pairedData.count) days with both readings. \(ChartSummary.correlation(correlationCoefficient)).")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 160)
            } else {
                VStack {
                    Spacer()
                    Text("Not enough overlapping data points")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 190)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .ruled()
    }
}

#Preview {
    NavigationStack {
        CorrelationsView()
    }
    .modelContainer(for: [Measurement.self, Medication.self, MedicationLog.self, Habit.self, HabitLog.self, Biomarker.self, Condition.self, DietPlan.self, MetricRange.self, VaultDocument.self, HealthMemory.self, Conversation.self], inMemory: true)
}
