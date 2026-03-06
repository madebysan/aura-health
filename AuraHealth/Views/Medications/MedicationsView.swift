import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Medication.name)
    private var medications: [Medication]

    @State private var typeFilter: MedicationType?
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var editingMedication: Medication?

    private var filteredMedications: [Medication] {
        medications.filter { med in
            let matchesType = typeFilter == nil || med.type == typeFilter
            let matchesActive = showArchived || med.active
            return matchesType && matchesActive
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterPill(label: "All", isActive: typeFilter == nil) {
                            withAnimation(AppAnimation.viewSwitch) { typeFilter = nil }
                        }
                        ForEach(MedicationType.allCases, id: \.self) { type in
                            FilterPill(label: type.displayName, isActive: typeFilter == type) {
                                withAnimation(AppAnimation.viewSwitch) { typeFilter = type }
                            }
                        }
                        Divider().frame(height: 20)
                        Toggle("Archived", isOn: $showArchived)
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }

                if filteredMedications.isEmpty {
                    EmptyStateView(
                        icon: "pills",
                        title: "No Medications",
                        message: "Add your prescriptions, supplements, and OTC medications.",
                        actionLabel: "Add Medication",
                        action: { showingAddSheet = true }
                    )
                    .padding(.top, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 500))], spacing: 10) {
                        ForEach(Array(filteredMedications.enumerated()), id: \.element.id) { index, medication in
                            MedicationCardView(medication: medication)
                                .onTapGesture { editingMedication = medication }
                                .staggeredAppearance(index: index)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Medications")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            MedicationFormSheet()
        }
        .sheet(item: $editingMedication) { medication in
            MedicationFormSheet(medication: medication)
        }
    }
}

// MARK: - Medication Card

struct MedicationCardView: View {
    let medication: Medication

    private var typeColor: Color {
        switch medication.type {
        case .rx: .blue
        case .supplement: .green
        case .otc: .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(typeColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(medication.name)
                        .font(.subheadline.weight(.medium))
                    if !medication.active {
                        StatusBadge(label: "Archived", color: .secondary)
                    }
                }
                HStack(spacing: 8) {
                    if !medication.dosage.isEmpty {
                        Text(medication.dosage)
                    }
                    Text(medication.frequency.displayName)
                    Text(medication.timing.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(label: medication.type.displayName, color: typeColor, style: .outlined)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .cardStyle(padding: 12, cornerRadius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverCard()
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
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Dosage", text: $dosage)
                    TextField("Condition", text: $condition)
                }
                Section {
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
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Has End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
                if isEditing {
                    Section { Toggle("Active", isOn: $active) }
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
