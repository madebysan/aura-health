import SwiftUI
import SwiftData

struct ConditionsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Condition.name)
    private var conditions: [Condition]

    @Query(sort: \DietPlan.name)
    private var dietPlans: [DietPlan]

    @State private var selectedTab = 0
    @State private var showingAddCondition = false
    @State private var showingAddDiet = false
    @State private var editingCondition: Condition?
    @State private var editingDiet: DietPlan?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("Conditions").tag(0)
                Text("Diet Plans").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                if selectedTab == 0 {
                    conditionsTab
                } else {
                    dietTab
                }
            }
        }
        .navigationTitle("Conditions & Diet")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if selectedTab == 0 { showingAddCondition = true }
                    else { showingAddDiet = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCondition) { ConditionFormSheet() }
        .sheet(item: $editingCondition) { ConditionFormSheet(condition: $0) }
        .sheet(isPresented: $showingAddDiet) { DietPlanFormSheet() }
        .sheet(item: $editingDiet) { DietPlanFormSheet(dietPlan: $0) }
    }

    // MARK: - Conditions

    private var conditionsTab: some View {
        VStack(spacing: 10) {
            if conditions.isEmpty {
                EmptyStateView(
                    icon: "stethoscope",
                    title: "No Conditions",
                    message: "Track your health conditions and their status.",
                    actionLabel: "Add Condition",
                    action: { showingAddCondition = true }
                )
            } else {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(conditionColor(condition.status))
                            .frame(width: 4, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(condition.name).font(.subheadline.weight(.medium))
                            if let date = condition.diagnosedDate {
                                Text("Diagnosed: \(date, format: .dateTime.month(.abbreviated).year())")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        StatusBadge(label: condition.status.displayName, color: conditionColor(condition.status))
                    }
                    .cardStyle(padding: 12, cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { editingCondition = condition }
                    .hoverCard()
                    .staggeredAppearance(index: index)
                }
            }
        }
        .padding()
    }

    // MARK: - Diet Plans

    private var dietTab: some View {
        VStack(spacing: 10) {
            if dietPlans.isEmpty {
                EmptyStateView(
                    icon: "fork.knife",
                    title: "No Diet Plans",
                    message: "Create a diet plan to track what you eat.",
                    actionLabel: "Add Diet Plan",
                    action: { showingAddDiet = true }
                )
            } else {
                ForEach(Array(dietPlans.enumerated()), id: \.element.id) { index, plan in
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 22, height: 22)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name).font(.subheadline.weight(.medium))
                            if !plan.dietType.isEmpty {
                                Text(plan.dietType).font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        StatusBadge(
                            label: plan.active ? "Active" : "Archived",
                            color: plan.active ? .green : .secondary
                        )
                    }
                    .cardStyle(padding: 12, cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { editingDiet = plan }
                    .hoverCard()
                    .staggeredAppearance(index: index)
                }
            }
        }
        .padding()
    }

    private func conditionColor(_ status: ConditionStatus) -> Color {
        switch status {
        case .active: AppColors.statusRed
        case .managed: AppColors.statusOrange
        case .resolved: AppColors.statusGreen
        }
    }
}

// MARK: - Condition Form

struct ConditionFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var condition: Condition?

    @State private var name = ""
    @State private var status: ConditionStatus = .active
    @State private var hasDiagnosedDate = false
    @State private var diagnosedDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Condition Name", text: $name)
                Picker("Status", selection: $status) {
                    ForEach(ConditionStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Diagnosed Date", isOn: $hasDiagnosedDate)
                if hasDiagnosedDate {
                    DatePicker("Date", selection: $diagnosedDate, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(condition != nil ? "Edit Condition" : "Add Condition")
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
                guard let c = condition else { return }
                name = c.name; status = c.status; notes = c.notes
                if let d = c.diagnosedDate { hasDiagnosedDate = true; diagnosedDate = d }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func save() {
        if let condition {
            condition.name = name; condition.status = status
            condition.diagnosedDate = hasDiagnosedDate ? diagnosedDate : nil
            condition.notes = notes
        } else {
            modelContext.insert(Condition(name: name, status: status,
                diagnosedDate: hasDiagnosedDate ? diagnosedDate : nil, notes: notes))
        }
        dismiss()
    }
}

// MARK: - Diet Plan Form

struct DietPlanFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var dietPlan: DietPlan?

    @State private var name = ""
    @State private var dietType = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var active = true
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Plan Name", text: $name)
                TextField("Diet Type (Mediterranean, Keto, etc.)", text: $dietType)
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                Toggle("Has End Date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                }
                Toggle("Active", isOn: $active)
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(dietPlan != nil ? "Edit Diet Plan" : "Add Diet Plan")
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
                guard let d = dietPlan else { return }
                name = d.name; dietType = d.dietType; active = d.active; notes = d.notes
                startDate = d.startDate ?? Date()
                if let end = d.endDate { hasEndDate = true; endDate = end }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func save() {
        if let dietPlan {
            dietPlan.name = name; dietPlan.dietType = dietType
            dietPlan.startDate = startDate; dietPlan.endDate = hasEndDate ? endDate : nil
            dietPlan.active = active; dietPlan.notes = notes
        } else {
            modelContext.insert(DietPlan(name: name, dietType: dietType,
                startDate: startDate, endDate: hasEndDate ? endDate : nil, notes: notes))
        }
        dismiss()
    }
}
