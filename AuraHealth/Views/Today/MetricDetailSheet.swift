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
    @State private var range: TimeRange = .month
    @State private var showAllHistory = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroValueSize: CGFloat = 52

    private var history: [Measurement] {
        allMeasurements.filter { $0.metricType == metricType }
    }

    private var latest: Measurement? { history.first }
    private var previous: Measurement? { history.count > 1 ? history[1] : nil }

    /// Readings in the selected chart range, oldest first.
    private var chartData: [Measurement] {
        guard let start = range.startDate else { return history.reversed() }
        return history.filter { $0.timestamp >= start }.reversed()
    }

    /// The ranges offered above the chart (Vitals itself no longer has range tabs).
    private static let ranges: [TimeRange] = [.week, .month, .quarter, .year]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let latest {
                        // Large current value
                        VStack(alignment: .leading, spacing: 4) {
                            Text(latest.displayValue)
                                .font(.system(size: heroValueSize, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(Notebook.ink)
                                .contentTransition(.numericText())

                            Text("\(metricType.unit) · \(latest.timestamp.formatted(.relative(presentation: .named)))")
                                .font(Notebook.mono(.footnote))
                                .foregroundStyle(Notebook.inkSecondary)

                            // Status
                            let position = metricType.rangePosition(of: latest.value)
                            StatusWord(text: position.label.lowercased(), color: position.wordColor)
                                .padding(.top, 6)
                        }
                        .notebookBlock()

                        // Delta from previous
                        if let previous {
                            deltaSection(latest: latest, previous: previous)
                                .notebookBlock()
                        }

                        // Reference range bar
                        rangeBar(value: latest.value)
                            .notebookBlock()

                        // Trend chart with its own range
                        if history.count > 1 {
                            trendChart
                                .notebookBlock()
                        }

                        // History list
                        historySection
                            .notebookBlock()

                        // About this metric
                        metricContextSection
                            .notebookBlock()
                    }

                    // Add Measurement button
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Measurement", image: "ph.plus")
                    }
                    .buttonStyle(NotebookPrimaryButtonStyle())
                    .padding(.top, 24)

                    // Chat about this metric
                    if let latest {
                        Button {
                            let context = "Tell me about my \(metricType.displayName) of \(latest.displayValue) \(metricType.unit). Is this in a healthy range? Any trends I should know about?"
                            NotificationCenter.default.post(name: .switchToChat, object: context)
                            dismiss()
                        } label: {
                            Label("Chat about this", image: "ph.chat-circle")
                        }
                        .buttonStyle(NotebookSecondaryButtonStyle())
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Notebook.paperRaised.ignoresSafeArea())
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

    // MARK: - About This Metric

    @State private var contextExpanded = false

    private var metricContextSection: some View {
        let ctx = metricType.context
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(AppAnimation.expand) {
                    contextExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("About \(metricType.displayName)")
                        .kicker()
                    Spacer()
                    Image("ph.caret-down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(contextExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if contextExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ctx.description)
                        .font(.subheadline)
                        .foregroundStyle(Notebook.inkSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(ctx.whyItMatters)
                            .font(.subheadline)
                            .foregroundStyle(Notebook.inkSecondary)
                    }

                    Text("Educational context only. Consult a qualified healthcare professional before making medical decisions.")
                        .font(Notebook.mono(.caption2))
                        .foregroundStyle(Notebook.inkSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reference range")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(ctx.rangeExplanation)
                            .font(.subheadline)
                            .foregroundStyle(Notebook.inkSecondary)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
            color = diff > 0 ? Notebook.inRange : (diff < 0 ? Notebook.near : Notebook.inkSecondary)
        case .heartRate, .strain:
            color = diff < 0 ? Notebook.inRange : (diff > 0 ? Notebook.near : Notebook.inkSecondary)
        default:
            color = .secondary
        }

        let iconName = diff > 0 ? "ph.arrow-up-right" : (diff < 0 ? "ph.arrow-down-right" : "ph.arrow-right")

        return HStack {
            Text("Since last reading")
                .kicker()
            Spacer()
            HStack(spacing: 4) {
                Image(iconName)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(formatted)
                    .font(Notebook.mono(.subheadline, weight: .medium))
            }
            .foregroundStyle(color)
        }
    }

    // MARK: - Range Bar

    private func rangeBar(value: Double) -> some View {
        let range = metricType.defaultRange
        return ReferenceRangeBar(
            value: value,
            low: range.low == 0 ? nil : range.low,
            high: range.high,
            valueColor: metricType.rangePosition(of: value).color,
            unit: metricType.unit,
            title: "Typical range"
        )
    }

    // MARK: - Trend Chart

    private var yDomain: ClosedRange<Double> {
        var allValues = chartData.map(\.value)
        allValues.append(contentsOf: chartData.compactMap(\.value2))
        guard let lo = allValues.min(), let hi = allValues.max() else { return 0...100 }
        let padding = max((hi - lo) * 0.15, 5)
        return max(lo - padding, 0)...(hi + padding)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            UnderlineTabs(options: Self.ranges, selection: $range) { $0.rawValue }

            if chartData.count < 2 {
                Text("Not enough readings in this range.")
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
            Chart {
                // The typical band only when it sits inside the plot; a generic default
                // wider than the data (weight 50–100 kg) would just fill the chart.
                if bandFitsPlot {
                    RectangleMark(
                        yStart: .value("Low", metricType.defaultRange.low),
                        yEnd: .value("High", metricType.defaultRange.high)
                    )
                    .foregroundStyle(Notebook.band.opacity(0.5))
                }

                ForEach(chartData, id: \.id) { measurement in
                if metricType == .bloodPressure {
                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Systolic", measurement.value),
                        series: .value("Reading", "Systolic")
                    )
                    .foregroundStyle(Notebook.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)

                    if let diastolic = measurement.value2 {
                        LineMark(
                            x: .value("Date", measurement.timestamp),
                            y: .value("Diastolic", diastolic),
                            series: .value("Reading", "Diastolic")
                        )
                        .foregroundStyle(Notebook.inkSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .interpolationMethod(.monotone)
                    }
                } else {
                    LineMark(
                        x: .value("Date", measurement.timestamp),
                        y: .value("Value", measurement.value)
                    )
                    .foregroundStyle(Notebook.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
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
            .accessibilityLabel("\(metricType.displayName), \(range.rawValue)")
            .accessibilityValue(ChartSummary.trend(points: chartData.map { ($0.timestamp, $0.value) }, unit: metricType.unit))
            }
        }
    }

    private var bandFitsPlot: Bool {
        let band = metricType.defaultRange
        return yDomain.contains(band.low) && yDomain.contains(band.high)
    }

    // MARK: - History

    @State private var measurementToDelete: Measurement?

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .kicker()

            let shown = showAllHistory ? history : Array(history.prefix(10))
            ForEach(shown, id: \.id) { measurement in
                HStack {
                    Text(measurement.timestamp, format: .dateTime.month(.abbreviated).day().year())
                        .font(Notebook.mono(.subheadline))

                    if !measurement.notes.isEmpty {
                        Image("ph.note")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text("\(measurement.displayValue) \(metricType.unit)")
                        .font(Notebook.mono(.subheadline, weight: .medium))

                    let position = metricType.rangePosition(of: measurement.value)
                    if position != .within {
                        Text(position == .above ? "↑" : "↓")
                            .font(Notebook.mono(.subheadline))
                            .foregroundStyle(position.color)
                            .accessibilityLabel(position.label)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        measurementToDelete = measurement
                    } label: {
                        Label("Delete", image: "ph.trash")
                    }
                }

                if measurement.id != shown.last?.id {
                    Divider()
                }
            }

            if history.count > 10 {
                Button(showAllHistory ? "Show fewer" : "Show all (\(history.count))") {
                    withAnimation(AppAnimation.expand) { showAllHistory.toggle() }
                }
                .font(Notebook.mono(.caption))
                .underline()
                .foregroundStyle(Notebook.inkSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .confirmationDialog("Delete this measurement?", isPresented: .init(
            get: { measurementToDelete != nil },
            set: { if !$0 { measurementToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let measurement = measurementToDelete {
                    modelContext.delete(measurement)
                    try? modelContext.save()
                    measurementToDelete = nil
                }
            }
        } message: {
            if let m = measurementToDelete {
                Text("Delete \(metricType.displayName) entry: \(m.displayValue) \(metricType.unit) from \(m.timestamp.formatted(.dateTime.month(.abbreviated).day().year()))?")
            }
        }
    }
}
