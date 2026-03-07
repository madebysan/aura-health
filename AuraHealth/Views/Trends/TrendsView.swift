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
            VStack(spacing: 20) {
                // Range selector
                HStack(spacing: 6) {
                    ForEach(TimeRange.allCases) { range in
                        FilterPill(label: range.rawValue, isActive: selectedRange == range) {
                            withAnimation(AppAnimation.viewSwitch) {
                                selectedRange = range
                            }
                        }
                    }
                    Spacer()
                }

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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520))], spacing: 14) {
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
            .padding()
        }
        .navigationTitle("Correlations")
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
                Image(systemName: metricType.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(metricType.iconColor)
                    .frame(width: 22, height: 22)
                    .background(metricType.iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                Text(metricType.displayName)
                    .font(.headline)

                Spacer()

                Text("\(measurements.count) pts")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
            }

            // Chart
            Chart(sortedData, id: \.id) { measurement in
                if metricType == .bloodPressure {
                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Systolic", measurement.value)
                    )
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)

                    if let diastolic = measurement.value2 {
                        LineMark(
                            x: .value("Date", measurement.timestamp),
                            y: .value("Diastolic", diastolic)
                        )
                        .foregroundStyle(Color.blue.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                    }
                } else {
                    AreaMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Value", measurement.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metricType.iconColor.opacity(0.1), metricType.iconColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Value", measurement.value)
                    )
                    .foregroundStyle(metricType.iconColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
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

            // Stats
            HStack(spacing: 0) {
                statPill("Avg", value: stats.avg, color: metricType.iconColor)
                Spacer()
                statPill("Min", value: stats.min, color: .secondary)
                Spacer()
                statPill("Max", value: stats.max, color: .secondary)
            }
        }
        .cardStyle()
        .hoverCard()
    }

    private func statPill(_ label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value))
                .font(.callout.monospacedDigit().bold())
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
                Text("\(pairedData.count) pts")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
            }

            if pairedData.count >= 3 {
                HStack {
                    Spacer()
                    let r = correlationCoefficient
                    Text("r = \(String(format: "%.2f", r))")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(abs(r) > 0.5 ? Color.accentColor : .secondary)
                }

                Chart(pairedData.indices, id: \.self) { i in
                    PointMark(
                        x: .value(typeA.displayName, pairedData[i].a),
                        y: .value(typeB.displayName, pairedData[i].b)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .symbolSize(30)
                }
                .chartXAxisLabel(typeA.displayName)
                .chartYAxisLabel(typeB.displayName)
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
                Text("Not enough overlapping data points")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .hoverCard()
    }
}

#Preview {
    NavigationStack {
        CorrelationsView()
    }
    .modelContainer(for: [Measurement.self, Medication.self, MedicationLog.self, Habit.self, HabitLog.self, Biomarker.self, Condition.self, DietPlan.self, MetricRange.self, VaultDocument.self, HealthMemory.self, Conversation.self], inMemory: true)
}
