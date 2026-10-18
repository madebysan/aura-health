import SwiftUI
import SwiftData
import Charts

// MARK: - Vitals Summary

/// What the top of Vitals says: which recent readings are outside their typical
/// range, and one plain sentence about them. Pure, so it can be tested.
enum VitalsSummary {
    struct Flag: Equatable {
        let metric: MetricType
        let position: RangePosition
    }

    /// Readings older than this are "last logged", not current, so they never flag.
    static let currentDays = 7
    /// Metrics with no reading for this long leave the Vitals list until the next one.
    static let visibleDays = 30

    static func isWithin(days: Int, of measurement: Measurement?, now: Date = Date()) -> Bool {
        guard let measurement,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)
        else { return false }
        return measurement.timestamp >= cutoff
    }

    /// Current readings outside their typical range, in list order.
    static func flags(order: [MetricType], latest: (MetricType) -> Measurement?, now: Date = Date()) -> [Flag] {
        order.compactMap { metric in
            guard let reading = latest(metric), isWithin(days: currentDays, of: reading, now: now) else { return nil }
            let position = metric.rangePosition(of: reading.value)
            return position == .above || position == .below ? Flag(metric: metric, position: position) : nil
        }
    }

    /// "Blood pressure and heart rate are above your typical range, and sleep duration is below it."
    static func sentence(flags: [Flag], hasReadings: Bool) -> String {
        guard hasReadings else { return "No readings yet. Connect Apple Health or add a measurement." }
        let above = flags.filter { $0.position == .above }.map { name($0.metric) }
        let below = flags.filter { $0.position == .below }.map { name($0.metric) }
        guard !above.isEmpty || !below.isEmpty else { return "Everything is within your typical range." }
        let text: String
        switch (above.isEmpty, below.isEmpty) {
        case (false, true): text = "\(list(above)) \(verb(above)) above your typical range."
        case (true, false): text = "\(list(below)) \(verb(below)) below your typical range."
        default: text = "\(list(above)) \(verb(above)) above your typical range, and \(list(below)) \(verb(below)) below it."
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Lowercases ordinary names ("Blood Pressure" → "blood pressure") but keeps acronyms ("HRV", "SpO2").
    static func name(_ metric: MetricType) -> String {
        metric.displayName.split(separator: " ").map { word in
            word.dropFirst().contains(where: \.isUppercase) ? String(word) : word.lowercased()
        }.joined(separator: " ")
    }

    private static func verb(_ items: [String]) -> String { items.count == 1 ? "is" : "are" }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
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
                Text(headerLine)
                    .kicker()
                    .padding(.bottom, 10)

                todayContent
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
                    Image("ph.sliders-horizontal")
                }
                .help("Choose which cards to show")
                .accessibilityLabel("Choose Visible Vital Cards")
            }
            ToolbarItem(placement: .automatic) {
                // Metrics without recent readings leave the list, so adding lives here.
                Menu {
                    ForEach(visibleMetrics.filter { !Self.autoOnlyMetrics.contains($0) }) { metric in
                        Button(metric.displayName) { selectedMetricType = metric }
                    }
                } label: {
                    Image("ph.plus")
                }
                .accessibilityLabel("Add Measurement")
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

    /// Tips are notes that aren't flags ("You haven't logged Weight in 9 days").
    /// Flags now live in the Flagged group, so only the first open tip is shown.
    private var activeTip: SuggestedStep? {
        generateSuggestedSteps().first { $0.type != .warning && !dismissedInsights.contains($0.message) }
    }

    private var flags: [VitalsSummary.Flag] {
        VitalsSummary.flags(order: todayVisibleMetrics) { latestMeasurement(for: $0) }
    }

    private var headerLine: String {
        let date = Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        let count = flags.count
        return count == 0 ? date : "\(date) · \(count) to look at"
    }

    private var todayContent: some View {
        let flagged = flags.map(\.metric)
        let others = todayVisibleMetrics.filter { !flagged.contains($0) }
        return VStack(alignment: .leading, spacing: 0) {
            // 1. What changed, in one sentence
            Text(VitalsSummary.sentence(flags: flags, hasReadings: !allMeasurements.isEmpty))
                .font(.body)
                .foregroundStyle(Notebook.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled()
                .staggeredAppearance(index: 0)

            // 2. One tip at most, dismissible
            if let tip = activeTip {
                NoteLine(text: tip.message, tag: "Tip", tagColor: Notebook.inkSecondary) {
                    withAnimation(AppAnimation.collapse) { dismissInsight(tip.message) }
                }
                .transition(.opacity)
            }

            // 3. Flagged metrics lead, everything else follows
            if !flagged.isEmpty {
                NotebookSectionHeader(title: "Flagged", trailing: "\(flagged.count)")
                    .padding(.top, 8)
                metricRows(flagged, startIndex: 1)
            }
            if !others.isEmpty {
                NotebookSectionHeader(title: flagged.isEmpty ? "Measures" : "Everything else")
                    .padding(.top, 8)
                metricRows(others, startIndex: flagged.count + 1)
            }
            if todayVisibleMetrics.isEmpty && !allMeasurements.isEmpty {
                Text("No readings in the last \(VitalsSummary.visibleDays) days. Use + to add one.")
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
                    .padding(.top, 16)
            }
        }
    }

    private func metricRows(_ metrics: [MetricType], startIndex: Int) -> some View {
        ForEach(Array(metrics.enumerated()), id: \.element) { index, metricType in
            MetricCardView(
                metricType: metricType,
                latest: latestMeasurement(for: metricType),
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
                    Label("Add Measurement", image: "ph.plus")
                }
            }
            .staggeredAppearance(index: index + startIndex)
        }
    }

    // MARK: - Auto-only Metrics (hide when no data)

    /// Metrics that only arrive from integrations (Apple Health) and can't be added by hand.
    private static let autoOnlyMetrics: Set<MetricType> = [.activeMinutes, .recovery, .strain, .sleepScore]

    /// Only metrics with a reading in the last 30 days; they return with the next reading.
    private var todayVisibleMetrics: [MetricType] {
        visibleMetrics.filter { VitalsSummary.isWithin(days: VitalsSummary.visibleDays, of: latestMeasurement(for: $0)) }
    }

    // MARK: - Data Helpers (cached by type)

    /// Measurements grouped by MetricType — computed once and reused
    private var measurementsByType: [MetricType: [Measurement]] {
        Dictionary(grouping: allMeasurements, by: \.metricType)
    }

    private func latestMeasurement(for type: MetricType) -> Measurement? {
        measurementsByType[type]?.first
    }

    private func recentValues(for type: MetricType, days: Int) -> [Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        guard let matching = measurementsByType[type] else { return [] }
        return matching
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.value)
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

// MARK: - Suggested Step (flag or tip)

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
                                Image(metricType.iconName)
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
