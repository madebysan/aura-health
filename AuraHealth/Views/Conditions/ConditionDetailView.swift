import SwiftUI
import SwiftData

// MARK: - Condition Page

/// One condition with the records linked to it, side by side: lab markers,
/// vitals, meds and supplements, habits and notes. It shows records only and
/// never judges how the condition is going.
struct ConditionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let condition: Condition

    @Query(sort: \Biomarker.testDate, order: .reverse)
    private var biomarkers: [Biomarker]

    @Query(sort: \Measurement.timestamp, order: .reverse)
    private var measurements: [Measurement]

    @State private var showingEdit = false
    @State private var showingLinks = false
    @State private var showingDeleteConfirm = false
    @State private var selectedBiomarker: Biomarker?
    @State private var detailMetric: MetricType?
    @State private var addMetric: MetricType?
    @State private var editingMedication: Medication?
    @State private var editingHabit: Habit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if condition.hasLinks {
                    labsSection
                    vitalsSection
                    medicationsSection
                    habitsSection
                } else {
                    emptyLinks
                }

                if !condition.notes.isEmpty {
                    NotebookSectionHeader(title: "Notes")
                    Text(condition.notes)
                        .font(.callout)
                        .foregroundStyle(Notebook.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ruled()
                }

                if condition.hasLinks {
                    Button("Link a lab, vital, med or habit") { showingLinks = true }
                        .buttonStyle(NotebookSecondaryButtonStyle())
                        .padding(.top, 24)
                }

                Text("Your records side by side. Aura doesn't judge how a condition is going; talk with your clinician about what they mean.")
                    .font(Notebook.mono(.caption2))
                    .foregroundStyle(Notebook.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle(condition.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEdit = true } label: { Label("Edit Condition", image: "ph.pencil-simple") }
                    Button { showingLinks = true } label: { Label("Link Records", image: "ph.link") }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("Delete", image: "ph.trash") }
                } label: {
                    Image("ph.dots-three")
                }
                .accessibilityLabel("Condition actions")
            }
        }
        .sheet(isPresented: $showingEdit) { ConditionFormSheet(condition: condition) }
        .sheet(isPresented: $showingLinks) { ConditionLinkSheet(condition: condition) }
        .sheet(item: $selectedBiomarker) { bio in
            BiomarkerDetailSheet(marker: bio.marker, biomarkers: biomarkers)
        }
        .sheet(item: $detailMetric) { MetricDetailSheet(metricType: $0) }
        .sheet(item: $addMetric) { AddMeasurementSheet(metricType: $0) }
        .sheet(item: $editingMedication) { MedicationFormSheet(medication: $0) }
        .sheet(item: $editingHabit) { HabitFormSheet(habit: $0) }
        .confirmationDialog(
            "Delete \(condition.name)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Condition", role: .destructive) {
                modelContext.delete(condition)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the condition and its notes. Linked labs, vitals, meds and habits stay.")
        }
    }

    // MARK: - Header

    private var header: some View {
        var parts = [condition.status.displayName.lowercased()]
        if let date = condition.diagnosedDate {
            parts.append("since \(date.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return Text(parts.joined(separator: " · "))
            .kicker()
            .padding(.bottom, 4)
            .accessibilityLabel("Status: \(parts.joined(separator: ", "))")
    }

    private var emptyLinks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing linked yet. Link the lab markers, vitals, meds and habits you keep an eye on for \(condition.name), and they'll show here together.")
                .font(.callout)
                .foregroundStyle(Notebook.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Link Records") { showingLinks = true }
                .buttonStyle(NotebookPrimaryButtonStyle())
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
    }

    // MARK: - Labs

    @ViewBuilder
    private var labsSection: some View {
        if !condition.trackedMarkers.isEmpty {
            NotebookSectionHeader(title: "Labs", trailing: "\(condition.trackedMarkers.count)")
            ForEach(condition.trackedMarkers, id: \.self) { marker in
                let history = biomarkers.filter { ConditionSuggestions.sameMarker($0.marker, marker) }
                if let latest = history.first {
                    Button { selectedBiomarker = latest } label: {
                        BiomarkerCardView(biomarker: latest, previous: history.dropFirst().first, historyCount: history.count)
                    }
                    .buttonStyle(.plain)
                } else {
                    placeholderRow(name: marker, detail: "no result yet")
                }
            }
        }
    }

    // MARK: - Vitals

    @ViewBuilder
    private var vitalsSection: some View {
        let metrics = condition.linkedMetrics
        if !metrics.isEmpty {
            NotebookSectionHeader(title: "Vitals", trailing: "\(metrics.count)")
            // Vitals rows rule their top edge; tuck the first under the header's rule
            // and close the group with a rule so it matches the other sections.
            VStack(spacing: 0) {
                ForEach(metrics) { metric in
                    let latest = measurements.first { $0.metricType == metric }
                    MetricCardView(
                        metricType: metric,
                        latest: latest,
                        recentValues: recentValues(for: metric),
                        onAdd: {
                            if latest != nil { detailMetric = metric } else { addMetric = metric }
                        }
                    )
                }
            }
            .padding(.top, -1)
            .ruled()
        }
    }

    private func recentValues(for metric: MetricType) -> [Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return measurements
            .filter { $0.metricType == metric && $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.value)
    }

    // MARK: - Meds and Habits

    @ViewBuilder
    private var medicationsSection: some View {
        let meds = condition.linkedMedications
        if !meds.isEmpty {
            NotebookSectionHeader(title: "Meds and Supplements", trailing: "\(meds.count)")
            ForEach(meds) { med in
                Button { editingMedication = med } label: {
                    MedicationCardView(medication: med)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var habitsSection: some View {
        let habits = condition.linkedHabits
        if !habits.isEmpty {
            NotebookSectionHeader(title: "Habits", trailing: "\(habits.count)")
            ForEach(habits) { habit in
                Button { editingHabit = habit } label: {
                    habitRow(habit)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Habit name with how many of the last seven days were done, today included.
    private func habitRow(_ habit: Habit) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let done = (0..<7).filter { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return false }
            return habit.log(on: day)?.done == true
        }.count

        let days = (Text("\(done)").font(Notebook.mono(.body, weight: .medium)).foregroundStyle(Notebook.ink)
            + Text("/7 days").font(Notebook.mono(.caption)).foregroundStyle(Notebook.inkSecondary))
            .monospacedDigit()

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(habit.active ? Notebook.ink : Notebook.inkSecondary)
                if !habit.active { StatusWord(text: "paused") }
                // At accessibility sizes the day count moves under the name
                if dynamicTypeSize.isAccessibilitySize { days }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if !dynamicTypeSize.isAccessibilitySize { days }

            Image("ph.caret-right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Notebook.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .ruled()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name), done \(done) of the last 7 days")
        .accessibilityHint("Opens the habit editor")
    }

    private func placeholderRow(name: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .font(.callout.weight(.medium))
                .foregroundStyle(Notebook.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusWord(text: detail)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .ruled()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Link Sheet

/// Choose the labs, vitals, meds and habits that belong on a condition's page.
/// Suggestions for common conditions are listed first and are never ticked
/// for the user.
struct ConditionLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    let condition: Condition

    @Query(sort: \Biomarker.marker) private var biomarkers: [Biomarker]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \Habit.name) private var habits: [Habit]

    @State private var markers: [String] = []
    @State private var metrics: Set<String> = []
    @State private var medicationIDs: Set<UUID> = []
    @State private var habitIDs: Set<UUID> = []

    private var suggestion: ConditionSuggestions.Suggestion? {
        ConditionSuggestions.suggestion(for: condition.name)
    }

    /// Every marker the user has a result for, one name per test.
    private var recordedMarkers: [String] {
        var names: [String] = []
        for bio in biomarkers where !names.contains(where: { ConditionSuggestions.sameMarker($0, bio.marker) }) {
            names.append(bio.marker)
        }
        return names
    }

    /// The user's own name for a suggested marker when they have a result for it.
    private func recordedName(for marker: String) -> String {
        recordedMarkers.first { ConditionSuggestions.sameMarker($0, marker) } ?? marker
    }

    private var suggestedMarkers: [String] {
        (suggestion?.markers ?? []).map(recordedName(for:))
    }

    private var otherMarkers: [String] {
        let suggested = suggestedMarkers
        let extra = markers.filter { m in !recordedMarkers.contains(where: { ConditionSuggestions.sameMarker($0, m) }) }
        return (recordedMarkers + extra).filter { m in !suggested.contains(where: { ConditionSuggestions.sameMarker($0, m) }) }
    }

    private var suggestedMetrics: [MetricType] { suggestion?.metrics ?? [] }

    var body: some View {
        NavigationStack {
            NotebookForm {
                if suggestion != nil {
                    Section {
                        ForEach(suggestedMarkers, id: \.self) { markerRow($0, detail: "lab") }
                        ForEach(suggestedMetrics) { metricRow($0, detail: "vital") }
                    } header: {
                        NotebookFormHeader("Often tracked with \(condition.name)")
                    } footer: {
                        Text("General suggestions, not advice. Tick only what you and your clinician watch.")
                            .font(.footnote)
                            .foregroundStyle(Notebook.inkSecondary)
                    }
                }

                if !otherMarkers.isEmpty {
                    Section(header: NotebookFormHeader("Labs")) {
                        ForEach(otherMarkers, id: \.self) { markerRow($0) }
                    }
                }

                Section(header: NotebookFormHeader("Vitals")) {
                    ForEach(MetricType.allCases.filter { !suggestedMetrics.contains($0) }) { metricRow($0) }
                }

                if !medications.isEmpty {
                    Section(header: NotebookFormHeader("Meds and Supplements")) {
                        ForEach(medications) { med in
                            checkRow(med.name, detail: med.dosage.isEmpty ? nil : med.dosage, isOn: medicationIDs.contains(med.id)) {
                                medicationIDs.formSymmetricDifference([med.id])
                            }
                        }
                    }
                }

                if !habits.isEmpty {
                    Section(header: NotebookFormHeader("Habits")) {
                        ForEach(habits) { habit in
                            checkRow(habit.name, detail: habit.active ? nil : "paused", isOn: habitIDs.contains(habit.id)) {
                                habitIDs.formSymmetricDifference([habit.id])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link Records")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                markers = condition.trackedMarkers
                metrics = Set(condition.trackedMetrics)
                medicationIDs = Set((condition.medications ?? []).map(\.id))
                habitIDs = Set((condition.habits ?? []).map(\.id))
            }
        }
    }

    private func markerRow(_ marker: String, detail: String? = nil) -> some View {
        let isOn = markers.contains { ConditionSuggestions.sameMarker($0, marker) }
        return checkRow(marker, detail: detail, isOn: isOn) {
            if isOn {
                markers.removeAll { ConditionSuggestions.sameMarker($0, marker) }
            } else {
                markers.append(marker)
            }
        }
    }

    private func metricRow(_ metric: MetricType, detail: String? = nil) -> some View {
        checkRow(metric.displayName, detail: detail, isOn: metrics.contains(metric.rawValue)) {
            metrics.formSymmetricDifference([metric.rawValue])
        }
    }

    private func checkRow(_ title: String, detail: String?, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AppAnimation.quickToggle) { toggle() }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Notebook.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
                NotebookCheckbox(isOn: isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Linked" : "Not linked")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        // Keep the order the user ticked them in, which is the order on the page
        condition.trackedMarkers = markers
        condition.trackedMetrics = MetricType.allCases.map(\.rawValue).filter(metrics.contains)
        condition.medications = medications.filter { medicationIDs.contains($0.id) }
        condition.habits = habits.filter { habitIDs.contains($0.id) }
        dismiss()
    }
}

// MARK: - Condition Picker (Meds and Habits forms)

/// "For condition" rows in the med and habit forms: one tick box per condition.
struct ConditionPickerSection: View {
    @Query(sort: \Condition.name) private var conditions: [Condition]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        if !conditions.isEmpty {
            Section(header: NotebookFormHeader("For condition")) {
                ForEach(conditions) { condition in
                    let isOn = selectedIDs.contains(condition.id)
                    Button {
                        withAnimation(AppAnimation.quickToggle) {
                            selectedIDs.formSymmetricDifference([condition.id])
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(condition.name)
                                .foregroundStyle(Notebook.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            NotebookCheckbox(isOn: isOn)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(condition.name)
                    .accessibilityValue(isOn ? "Linked" : "Not linked")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    /// The selected conditions, for saving into a med or habit.
    static func conditions(_ ids: Set<UUID>, in context: ModelContext) -> [Condition] {
        let all = (try? context.fetch(FetchDescriptor<Condition>())) ?? []
        return all.filter { ids.contains($0.id) }
    }
}
