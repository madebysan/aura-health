import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Measurement.timestamp, order: .reverse)
    private var allMeasurements: [Measurement]

    @Query(filter: #Predicate<Medication> { $0.active })
    private var activeMedications: [Medication]

    @Query(filter: #Predicate<Habit> { $0.active })
    private var activeHabits: [Habit]

    @State private var selectedMetricType: MetricType?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                healthScoreSection
                metricsSection
                suggestedStepsSection
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Today")
        #if os(macOS)
        .frame(minWidth: 600)
        #endif
        .sheet(item: $selectedMetricType) { metricType in
            AddMeasurementSheet(metricType: metricType)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addMeasurement)) { _ in
            selectedMetricType = .weight
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Health Score

    private var healthScoreSection: some View {
        HStack(spacing: 28) {
            HealthScoreRingView(
                score: dailyHealthScore,
                label: "Daily Health"
            )
            .staggeredAppearance(index: 0)

            VStack(alignment: .leading, spacing: 12) {
                scoreBreakdownRow(
                    icon: "arrow.counterclockwise.heart",
                    label: "Recovery",
                    value: latestValue(for: .recovery),
                    color: .green,
                    weight: "40%"
                )
                scoreBreakdownRow(
                    icon: "moon.fill",
                    label: "Sleep Score",
                    value: latestValue(for: .sleepScore),
                    color: .purple,
                    weight: "35%"
                )
                scoreBreakdownRow(
                    icon: "waveform.path.ecg.rectangle",
                    label: "HRV",
                    value: latestValue(for: .hrv),
                    color: .cyan,
                    weight: "25%"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
        .staggeredAppearance(index: 1)
    }

    private func scoreBreakdownRow(icon: String, label: String, value: Double?, color: Color, weight: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

            Text(label)
                .font(.subheadline)

            Spacer()

            if let value {
                Text("\(Int(value))")
                    .font(.subheadline.monospacedDigit().bold())
                    .contentTransition(.numericText())
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.quaternary)
            }

            Text(weight)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Metrics Grid

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Vitals")

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(Array(MetricType.allCases.enumerated()), id: \.element) { index, metricType in
                    MetricCardView(
                        metricType: metricType,
                        latest: latestMeasurement(for: metricType),
                        previous: previousMeasurement(for: metricType),
                        recentValues: recentValues(for: metricType, days: 7),
                        onAdd: { selectedMetricType = metricType }
                    )
                    .staggeredAppearance(index: index + 2)
                }
            }
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
                    DatePicker("Date & Time", selection: $timestamp)
                }

                Section("Value") {
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

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
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
        .frame(minWidth: 400, minHeight: 300)
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
        TodayView()
    }
    .modelContainer(for: [Measurement.self, Medication.self, MedicationLog.self, Habit.self, HabitLog.self, Biomarker.self, Condition.self, DietPlan.self, MetricRange.self, VaultDocument.self, HealthMemory.self, Conversation.self], inMemory: true)
}
