import SwiftUI
import SwiftData

struct ConditionsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Condition.name)
    private var conditions: [Condition]

    @State private var showingAddCondition = false
    @State private var editingCondition: Condition?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var activeCount: Int {
        conditions.filter { $0.status == .active }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if conditions.isEmpty {
                    EmptyStateView(
                        icon: "ph.stethoscope",
                        title: "No Conditions",
                        message: "Track your health conditions and their status.",
                        actionLabel: "Add Condition",
                        action: { showingAddCondition = true },
                        chatHint: "Try \"I have seasonal allergies, managed\" in Chat"
                    )
                } else {
                    NotebookSectionHeader(title: "Conditions", trailing: "\(activeCount) active")

                    ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                        Button {
                            editingCondition = condition
                        } label: {
                            conditionRow(condition)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(condition)
                            } label: {
                                Label("Delete", image: "ph.trash")
                            }
                        }
                        .staggeredAppearance(index: index)
                    }
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Conditions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddCondition = true } label: {
                    Image("ph.plus")
                }
                .accessibilityLabel("Add Condition")
            }
        }
        .sheet(isPresented: $showingAddCondition) { ConditionFormSheet() }
        .sheet(item: $editingCondition) { ConditionFormSheet(condition: $0) }
    }

    /// Name and diagnosis date, with the status written as a mono word.
    /// Active conditions read in ink; managed and resolved ones read quietly.
    private func conditionRow(_ condition: Condition) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            let status = StatusWord(
                text: condition.status.displayName.lowercased(),
                color: condition.status == .active ? Notebook.ink : Notebook.inkSecondary
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                if let date = condition.diagnosedDate {
                    Text("diagnosed \(date.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
                // At accessibility sizes the status word moves under the name
                if dynamicTypeSize.isAccessibilitySize { status }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if !dynamicTypeSize.isAccessibilitySize { status }

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
        .accessibilityHint("Opens the condition editor")
    }
}

// MARK: - Diet Plans View (standalone)

struct DietPlansView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DietPlan.name)
    private var dietPlans: [DietPlan]

    @State private var showingAddDiet = false
    @State private var editingDiet: DietPlan?
    /// The plan waiting for delete confirmation.
    @State private var planPendingDelete: DietPlan?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var activePlan: DietPlan? {
        dietPlans.first { $0.active }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if dietPlans.isEmpty {
                    EmptyStateView(
                        icon: "ph.fork-knife",
                        title: "No Diet Plans",
                        message: "Set up your diet to track which food categories you eat. This context helps when looking at correlations with your health data.",
                        actionLabel: "Set Up Diet",
                        action: { showingAddDiet = true }
                    )
                } else {
                    // Active plan header
                    if let plan = activePlan {
                        activePlanHeader(plan)
                            .staggeredAppearance(index: 0)

                        // Food categories
                        let approved = plan.allowedFoods
                        let avoided = plan.avoidFoods

                        if !approved.isEmpty {
                            foodSection(title: "Approved", foods: approved, plan: plan, isApproved: true)
                                .staggeredAppearance(index: 1)
                        }

                        if !avoided.isEmpty {
                            foodSection(title: "Avoided", foods: avoided, plan: plan, isApproved: false)
                                .staggeredAppearance(index: 2)
                        }
                    }

                    // Other plans
                    let otherPlans = dietPlans.filter { !$0.active }
                    if !otherPlans.isEmpty {
                        NotebookSectionHeader(title: "Other Plans", trailing: "\(otherPlans.count)")

                        ForEach(otherPlans) { plan in
                            planRow(plan)
                        }
                    }
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Diet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddDiet = true } label: {
                    Image("ph.plus")
                }
                .accessibilityLabel("Add Diet Plan")
            }
        }
        .sheet(isPresented: $showingAddDiet) { DietPlanFormSheet() }
        .sheet(item: $editingDiet) { DietPlanFormSheet(dietPlan: $0) }
        .confirmationDialog(
            "Delete \(planPendingDelete?.name ?? "diet plan")?",
            isPresented: Binding(
                get: { planPendingDelete != nil },
                set: { if !$0 { planPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: planPendingDelete
        ) { plan in
            Button("Delete Plan", role: .destructive) {
                withAnimation(AppAnimation.quickToggle) {
                    modelContext.delete(plan)
                }
                planPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { planPendingDelete = nil }
        } message: { plan in
            Text("This removes the \(plan.name) plan and its approved and avoided foods. Your other records stay.")
        }
    }

    // MARK: - Active Plan Header

    private func activePlanHeader(_ plan: DietPlan) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Active plan").kicker()
                Text(plan.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Notebook.ink)
                if !plan.dietType.isEmpty && plan.dietType != plan.name {
                    Text(plan.dietType)
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
                if let start = plan.startDate {
                    Text("since \(start.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                editingDiet = plan
            } label: {
                Image("ph.pencil-simple")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Notebook.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(plan.name)")

            Button {
                planPendingDelete = plan
            } label: {
                Image("ph.trash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Notebook.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(plan.name)")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.vertical, 18)
        .ruled()
    }

    // MARK: - Food Section

    /// One food per hairline row with a tick box: ticked when approved,
    /// crossed when avoided. Tapping moves the food to the other list.
    private func foodSection(title: String, foods: [String], plan: DietPlan, isApproved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NotebookSectionHeader(title: title, trailing: "\(foods.count)")

            ForEach(foods, id: \.self) { food in
                Button {
                    withAnimation(AppAnimation.quickToggle) {
                        toggleFood(food, plan: plan, currentlyApproved: isApproved)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(food)
                            .font(.callout)
                            .foregroundStyle(isApproved ? Notebook.ink : Notebook.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        NotebookCheckbox(isOn: isApproved, isCrossed: !isApproved)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .ruled()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(food)
                .accessibilityValue(isApproved ? "Approved" : "Avoided")
                .accessibilityHint(isApproved ? "Moves to Avoided" : "Moves to Approved")
                .help(isApproved ? "Tap to move to Avoided" : "Tap to move to Approved")
            }
        }
    }

    private func toggleFood(_ food: String, plan: DietPlan, currentlyApproved: Bool) {
        if currentlyApproved {
            plan.allowedFoods.removeAll { $0 == food }
            if !plan.avoidFoods.contains(food) {
                plan.avoidFoods.append(food)
                plan.avoidFoods.sort()
            }
        } else {
            plan.avoidFoods.removeAll { $0 == food }
            if !plan.allowedFoods.contains(food) {
                plan.allowedFoods.append(food)
                plan.allowedFoods.sort()
            }
        }
    }

    // MARK: - Plan Row

    private func planRow(_ plan: DietPlan) -> some View {
        Button {
            editingDiet = plan
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Notebook.ink)
                    if !plan.dietType.isEmpty {
                        Text(plan.dietType)
                            .font(Notebook.mono(.caption))
                            .foregroundStyle(Notebook.inkSecondary)
                    }
                    if dynamicTypeSize.isAccessibilitySize { StatusWord(text: "archived") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                if !dynamicTypeSize.isAccessibilitySize { StatusWord(text: "archived") }

                Image("ph.caret-right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Notebook.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the diet plan editor")
        .contextMenu {
            Button {
                plan.active = true
            } label: {
                Label("Set as Active", image: "ph.check-circle")
            }
            Button(role: .destructive) {
                planPendingDelete = plan
            } label: {
                Label("Delete", image: "ph.trash")
            }
        }
    }
}

// MARK: - Condition Form

struct ConditionFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var condition: Condition?

    @State private var name = ""
    @State private var searchText = ""
    @State private var isCustom = false
    @State private var status: ConditionStatus = .active
    @State private var hasDiagnosedDate = false
    @State private var diagnosedDate = Date()
    @State private var notes = ""

    private var isEditing: Bool { condition != nil }

    private var filteredConditions: [String] {
        guard !searchText.isEmpty else { return CommonCondition.allNames }
        return CommonCondition.search(searchText)
    }

    var body: some View {
        NavigationStack {
            NotebookForm {
                if isEditing || isCustom {
                    // Edit mode or custom: show text field
                    Section {
                        NotebookField("Condition", text: $name, prompt: "e.g. Hypertension")
                        PillSegmentedPicker(
                            options: ConditionStatus.allCases,
                            selection: $status,
                            label: { $0.displayName }
                        )
                    }
                } else {
                    // New condition: searchable picker
                    Section {
                        HStack(spacing: 8) {
                            Image("ph.magnifying-glass")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                            TextField("Search conditions...", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                    }

                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                            ForEach(filteredConditions, id: \.self) { conditionName in
                                let isSelected = name == conditionName
                                Button {
                                    withAnimation(AppAnimation.quickToggle) {
                                        name = isSelected ? "" : conditionName
                                    }
                                } label: {
                                    Text(conditionName)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Notebook.paper : Notebook.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            isSelected ? Notebook.ink : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.clear : Notebook.rule, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }

                        Button {
                            withAnimation(AppAnimation.quickToggle) {
                                isCustom = true
                                name = searchText
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image("ph.plus")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Notebook.ink)
                                Text("Custom condition")
                                    .font(.subheadline)
                                    .foregroundStyle(Notebook.ink)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !name.isEmpty {
                        Section {
                            PillSegmentedPicker(
                                options: ConditionStatus.allCases,
                                selection: $status,
                                label: { $0.displayName }
                            )
                        }
                    }
                }

                Section {
                    Toggle("Diagnosed Date", isOn: $hasDiagnosedDate)
                    if hasDiagnosedDate {
                        DatePicker("Date", selection: $diagnosedDate, displayedComponents: .date)
                    }
                }

                Section(header: NotebookFormHeader("Notes")) {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(isEditing ? "Edit Condition" : "Add Condition")
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
        .frame(minWidth: 460, minHeight: 480)
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
    @State private var selectedDietType: DietTypeOption = .mediterranean
    @State private var customDietType = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var active = true
    @State private var notes = ""

    private var resolvedDietType: String {
        selectedDietType == .custom ? customDietType : selectedDietType.rawValue
    }

    var body: some View {
        NavigationStack {
            NotebookForm {
                Section {
                    NotebookField("Plan name", text: $name, prompt: "e.g. Mediterranean")
                }

                Section(header: NotebookFormHeader("Diet Type")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(DietTypeOption.allCases) { option in
                            let isSelected = selectedDietType == option
                            Button {
                                withAnimation(AppAnimation.quickToggle) {
                                    selectedDietType = option
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(option.iconName)
                                        .font(.caption2.weight(.semibold))
                                        .accessibilityHidden(true)
                                    Text(option.rawValue)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .lineLimit(2)
                                }
                                .foregroundStyle(isSelected ? Notebook.paper : Notebook.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    isSelected ? Notebook.ink : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.clear : Notebook.rule, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }

                    if selectedDietType == .custom {
                        TextField("Enter diet name", text: $customDietType)
                    }
                }

                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Has End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }

                if dietPlan != nil {
                    Section {
                        Toggle("Active", isOn: $active)
                    }
                }

                Section(header: NotebookFormHeader("Notes")) {
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
                name = d.name; active = d.active; notes = d.notes
                startDate = d.startDate ?? Date()
                if let end = d.endDate { hasEndDate = true; endDate = end }
                // Restore diet type selection
                if let match = DietTypeOption.from(d.dietType) {
                    selectedDietType = match
                } else if !d.dietType.isEmpty {
                    selectedDietType = .custom
                    customDietType = d.dietType
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }

    private func save() {
        let approved = selectedDietType.defaultApproved.map(\.rawValue)
        let avoided = selectedDietType.defaultAvoided.map(\.rawValue)

        if let dietPlan {
            dietPlan.name = name; dietPlan.dietType = resolvedDietType
            dietPlan.startDate = startDate; dietPlan.endDate = hasEndDate ? endDate : nil
            dietPlan.active = active; dietPlan.notes = notes
            // Only reset food lists when diet type changes
            if dietPlan.allowedFoods.isEmpty && dietPlan.avoidFoods.isEmpty {
                dietPlan.allowedFoods = approved
                dietPlan.avoidFoods = avoided
            }
        } else {
            modelContext.insert(DietPlan(name: name, dietType: resolvedDietType,
                startDate: startDate, endDate: hasEndDate ? endDate : nil,
                allowedFoods: approved, avoidFoods: avoided, notes: notes))
        }
        dismiss()
    }
}
