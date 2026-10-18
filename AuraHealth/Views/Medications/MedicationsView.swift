import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Medication.name)
    private var medications: [Medication]

    @State private var showingAddSheet = false
    @State private var editingMedication: Medication?

    private var activeMedications: [Medication] { medications.filter(\.active) }
    private var archivedMedications: [Medication] { medications.filter { !$0.active } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if medications.isEmpty {
                    EmptyStateView(
                        icon: "ph.pill",
                        title: "No Medications",
                        message: "Add your prescriptions, supplements, and OTC medications.",
                        actionLabel: "Add Medication",
                        action: { showingAddSheet = true },
                        chatHint: "Try \"I take 500mg magnesium at night\" in Chat"
                    )
                    .padding(.top, 20)
                } else {
                    // Active first; archived ones follow in their own section (no type filter:
                    // every row already says Prescription, Supplement or OTC).
                    if !activeMedications.isEmpty {
                        NotebookSectionHeader(title: "Active", trailing: "\(activeMedications.count)")
                        medicationRows(activeMedications)
                    }
                    if !archivedMedications.isEmpty {
                        NotebookSectionHeader(title: "Archived", trailing: "\(archivedMedications.count)")
                            .padding(.top, 12)
                        medicationRows(archivedMedications)
                    }
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Medications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image("ph.plus")
                }
                .accessibilityLabel("Add Medication")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            MedicationFormSheet()
        }
        .sheet(item: $editingMedication) { medication in
            MedicationFormSheet(medication: medication)
        }
    }

    private func medicationRows(_ list: [Medication]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { index, medication in
            Button {
                editingMedication = medication
            } label: {
                MedicationCardView(medication: medication)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    medication.active.toggle()
                } label: {
                    Label(medication.active ? "Archive" : "Unarchive",
                          image: medication.active ? "ph.archive" : "ph.box-arrow-up")
                }
                Button(role: .destructive) {
                    modelContext.delete(medication)
                } label: {
                    Label("Delete", image: "ph.trash")
                }
            }
            .staggeredAppearance(index: index)
        }
    }
}

// MARK: - Medication Row

/// A hairline row: name, then dose and schedule in mono. The type is written
/// as a word, not a color.
struct MedicationCardView: View {
    let medication: Medication

    private var detail: String {
        var parts = [medication.type.displayName]
        if !medication.dosage.isEmpty { parts.append(medication.dosage) }
        parts.append(medication.frequency.displayName)
        parts.append(medication.timing.displayName)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(medication.active ? Notebook.ink : Notebook.inkSecondary)
                Text(detail)
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

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
        .accessibilityHint("Opens the medication editor")
    }
}

// MARK: - Medication Form

struct MedicationFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var medication: Medication?

    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency: MedicationFrequency = .daily
    @State private var condition = ""
    @State private var type: MedicationType = .rx
    @State private var timing: MedicationTiming = .anyTime
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var active = true

    var isEditing: Bool { medication != nil }

    var body: some View {
        NavigationStack {
            NotebookForm {
                Section(header: NotebookFormHeader("Medication")) {
                    NotebookField("Name", text: $name, prompt: "e.g. Vitamin D3")
                    NotebookField("Dosage", text: $dosage, prompt: "e.g. 500 mg")
                    NotebookField("Taken for", text: $condition, prompt: "e.g. Sleep, blood pressure")
                }

                Section(header: NotebookFormHeader("Schedule")) {
                    Picker("Type", selection: $type) {
                        ForEach(MedicationType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }

                    Picker("Frequency", selection: $frequency) {
                        ForEach(MedicationFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Timing", selection: $timing) {
                        ForEach(MedicationTiming.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }

                Section(header: NotebookFormHeader("Dates")) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Has End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }

                if isEditing {
                    Section(header: NotebookFormHeader("Status")) {
                        Toggle("Active", isOn: $active)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Medication" : "Add Medication")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear {
                guard let m = medication else { return }
                name = m.name; dosage = m.dosage; frequency = m.frequency
                condition = m.condition; type = m.type; timing = m.timing
                startDate = m.startDate ?? Date(); active = m.active
                if let end = m.endDate { hasEndDate = true; endDate = end }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 450)
        #endif
    }

    private func save() {
        if let medication {
            medication.name = name; medication.dosage = dosage
            medication.frequency = frequency; medication.condition = condition
            medication.type = type; medication.timing = timing
            medication.startDate = startDate
            medication.endDate = hasEndDate ? endDate : nil
            medication.active = active
        } else {
            modelContext.insert(Medication(name: name, dosage: dosage, frequency: frequency,
                condition: condition, type: type, timing: timing,
                startDate: startDate, endDate: hasEndDate ? endDate : nil))
        }
        dismiss()
    }
}
