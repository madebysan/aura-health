import SwiftUI
import SwiftData
import Charts

struct MetricDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let metricType: MetricType

    @Query(sort: \Measurement.timestamp, order: .reverse)
    private var allMeasurements: [Measurement]

    @State private var showingAddSheet = false

    private var history: [Measurement] {
        allMeasurements.filter { $0.metricType == metricType }
    }

    private var latest: Measurement? { history.first }
    private var previous: Measurement? { history.count > 1 ? history[1] : nil }

    private var last30Days: [Measurement] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return history.filter { $0.timestamp >= cutoff }.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let latest {
                        // Large current value
                        VStack(spacing: 6) {
                            Text(latest.displayValue)
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())

                            Text(metricType.unit)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            // Status
                            let range = metricType.defaultRange
                            let inRange = latest.value >= range.low && latest.value <= range.high
                            StatusBadge(
                                label: inRange ? "In Range" : "Out of Range",
                                color: inRange ? AppColors.statusGreen : AppColors.statusOrange
                            )

                            // Timestamp
                            Text(latest.timestamp, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 8)

                        // Delta from previous
                        if let previous {
                            deltaSection(latest: latest, previous: previous)
                                .cardStyle()
                        }

                        // Reference range bar
                        rangeBar(value: latest.value)
                            .cardStyle()

                        // Trend chart (last 30 days)
                        if last30Days.count > 1 {
                            trendChart
                                .cardStyle()
                        }

                        // History list
                        historySection
                            .cardStyle()
                    }

                    // Add Measurement button
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Measurement", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle(metricType.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddMeasurementSheet(metricType: metricType)
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
    }

    // MARK: - Delta Section

    private func deltaSection(latest: Measurement, previous: Measurement) -> some View {
        let diff = latest.value - previous.value
        let sign = diff > 0 ? "+" : ""
        let formatted: String
        if diff == diff.rounded() {
            formatted = "\(sign)\(Int(diff)) \(metricType.unit)"
        } else {
            formatted = "\(sign)\(String(format: "%.1f", diff)) \(metricType.unit)"
        }

        let color: Color
        switch metricType {
        case .recovery, .sleepScore, .hrv, .spo2, .sleepDuration, .steps, .activeMinutes:
            color = diff > 0 ? AppColors.statusGreen : (diff < 0 ? AppColors.statusOrange : .secondary)
        case .heartRate, .strain:
            color = diff < 0 ? AppColors.statusGreen : (diff > 0 ? AppColors.statusOrange : .secondary)
        default:
            color = .secondary
        }

        let iconName = diff > 0 ? "arrow.up.right" : (diff < 0 ? "arrow.down.right" : "arrow.right")

        return HStack {
            Text("vs Previous")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                Text(formatted)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(color)
        }
    }

    // MARK: - Range Bar

    private func rangeBar(value: Double) -> some View {
        let range = metricType.defaultRange
        let low = range.low
        let high = range.high
        let span = high - low
        let extendedMin = low - span * 0.3
        let extendedMax = high + span * 0.3

        return VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let fullRange = extendedMax - extendedMin
                let normalStart = CGFloat((low - extendedMin) / fullRange) * width
                let normalWidth = CGFloat(span / fullRange) * width
                let valueX = CGFloat((value - extendedMin) / fullRange) * width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusRed.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusGreen.opacity(0.2))
                        .frame(width: normalWidth)
                        .offset(x: normalStart)

                    Circle()
                        .fill(value >= low && value <= high ? AppColors.statusGreen : AppColors.statusOrange)
                        .shadow(color: (value >= low && value <= high ? AppColors.statusGreen : AppColors.statusOrange).opacity(0.4), radius: 4)
                        .frame(width: 14, height: 14)
                        .offset(x: Swift.max(0, Swift.min(valueX - 7, width - 14)))
                }
            }
            .frame(height: 14)

            HStack {
                Text(low == low.rounded() ? "\(Int(low))" : String(format: "%.1f", low))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Reference Range")
                    .font(.caption2).foregroundStyle(.quaternary)
                Spacer()
                Text(high == high.rounded() ? "\(Int(high))" : String(format: "%.1f", high))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Trend Chart

    private var yDomain: ClosedRange<Double> {
        var allValues = last30Days.map(\.value)
        allValues.append(contentsOf: last30Days.compactMap(\.value2))
        guard let lo = allValues.min(), let hi = allValues.max() else { return 0...100 }
        let padding = max((hi - lo) * 0.15, 5)
        return max(lo - padding, 0)...(hi + padding)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 30 Days")
                .font(.headline)

            Chart(last30Days, id: \.id) { measurement in
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
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
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
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)

            ForEach(history, id: \.id) { measurement in
                HStack {
                    Text(measurement.timestamp, format: .dateTime.month(.abbreviated).day().year())
                        .font(.subheadline)

                    if !measurement.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(measurement.displayValue)
                        .font(.subheadline.monospacedDigit().bold())

                    Text(metricType.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Status dot
                    let range = metricType.defaultRange
                    let inRange = measurement.value >= range.low && measurement.value <= range.high
                    Circle()
                        .fill(inRange ? AppColors.statusGreen : AppColors.statusOrange)
                        .frame(width: 7, height: 7)
                }

                if measurement.id != history.last?.id {
                    Divider()
                }
            }
        }
    }
}
