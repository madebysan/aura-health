import SwiftUI
import SwiftData

/// Health profile: the conditions someone lives with and how they eat.
/// Each condition opens a page with the records linked to it.
struct ConditionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Condition.name)
    private var conditions: [Condition]

    @Query(sort: \DietPlan.name)
    private var dietPlans: [DietPlan]

    @State private var showingAddCondition = false
    @State private var conditionPendingDelete: Condition?
    @State private var showingAddDiet = false
    @State private var editingDiet: DietPlan?
    @State private var planPendingDelete: DietPlan?

    private var currentConditions: [Condition] { conditions.filter { $0.status != .resolved } }
    private var resolvedConditions: [Condition] { conditions.filter { $0.status == .resolved } }
    private var activeCount: Int { conditions.filter { $0.status == .active }.count }

    private var activePlan: DietPlan? { dietPlans.first { $0.active } }
    private var pastPlans: [DietPlan] { dietPlans.filter { $0.id != activePlan?.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if conditions.isEmpty && dietPlans.isEmpty {
                    EmptyStateView(
                        icon: "ph.stethoscope",
                        title: "No Health Profile Yet",
                        message: "Add the conditions you live with and how you eat. Link labs, vitals, meds and habits to a condition to see them together.",
                        actionLabel: "Add Condition",
                        action: { showingAddCondition = true },
                        chatHint: "Try \"I have seasonal allergies, managed\" in Chat"
                    )
                    Button("Add How You Eat") { showingAddDiet = true }
                        .buttonStyle(NotebookSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                } else {
                    conditionsSection
                    howIEatSection
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Health Profile")
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
        .sheet(isPresented: $showingAddDiet) { DietPlanFormSheet() }
        .sheet(item: $editingDiet) { DietPlanFormSheet(dietPlan: $0) }
        .confirmationDialog(
            "Delete \(conditionPendingDelete?.name ?? "condition")?",
            isPresented: Binding(
                get: { conditionPendingDelete != nil },
                set: { if !$0 { conditionPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: conditionPendingDelete
        ) { condition in
            Button("Delete Condition", role: .destructive) {
                withAnimation(AppAnimation.quickToggle) { modelContext.delete(condition) }
                conditionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { conditionPendingDelete = nil }
        } message: { _ in
            Text("This removes the condition and its notes. Linked labs, vitals, meds and habits stay.")
        }
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
                withAnimation(AppAnimation.quickToggle) { modelContext.delete(plan) }
                planPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { planPendingDelete = nil }
        } message: { plan in
            Text("This removes the \(plan.name) plan and its avoided foods. Your other records stay.")
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        NotebookSectionHeader(title: "Conditions", trailing: conditions.isEmpty ? nil : "\(activeCount) active")

        if currentConditions.isEmpty && resolvedConditions.isEmpty {
            addRow("Add a condition") { showingAddCondition = true }
        }

        ForEach(Array(currentConditions.enumerated()), id: \.element.id) { index, condition in
            conditionLink(condition)
                .staggeredAppearance(index: index)
        }

        if !resolvedConditions.isEmpty {
            NotebookSectionHeader(title: "Resolved", trailing: "\(resolvedConditions.count)")
            ForEach(resolvedConditions) { conditionLink($0) }
        }
    }

    private func conditionLink(_ condition: Condition) -> some View {
        NavigationLink {
            ConditionDetailView(condition: condition)
        } label: {
            conditionRow(condition)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                conditionPendingDelete = condition
            } label: {
                Label("Delete", image: "ph.trash")
            }
        }
    }

    /// Name, then the diagnosis date and what's linked; the status is a mono word.
    /// Active conditions read in ink; managed and resolved ones read quietly.
    private func conditionRow(_ condition: Condition) -> some View {
        let status = StatusWord(
            text: condition.status.displayName.lowercased(),
            color: condition.status == .active ? Notebook.ink : Notebook.inkSecondary
        )
        // One line each, so the link counts never break mid-phrase
        let meta = [
            condition.diagnosedDate.map { "since \($0.formatted(.dateTime.month(.abbreviated).year()))" },
            condition.linkSummary,
        ].compactMap { $0 }

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                ForEach(meta, id: \.self) { line in
                    Text(line)
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
        .accessibilityHint("Opens the condition page")
    }

    // MARK: - How I Eat

    @ViewBuilder
    private var howIEatSection: some View {
        NotebookSectionHeader(title: "How I eat")

        if let plan = activePlan {
            Button { editingDiet = plan } label: {
                planRow(plan, isCurrent: true)
            }
            .buttonStyle(.plain)
            .contextMenu { planMenu(plan, isCurrent: true) }

            if !plan.avoidFoods.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Avoid").kicker()
                    Text(plan.avoidFoods.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(Notebook.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .ruled()
                .accessibilityElement(children: .combine)
            }

            if !plan.notes.isEmpty {
                Text(plan.notes)
                    .font(.callout)
                    .foregroundStyle(Notebook.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ruled()
            }
        } else {
            addRow("Add how you eat") { showingAddDiet = true }
        }

        if !pastPlans.isEmpty {
            NotebookSectionHeader(title: "Past plans", trailing: "\(pastPlans.count)")
            ForEach(pastPlans) { plan in
                Button { editingDiet = plan } label: {
                    planRow(plan, isCurrent: false)
                }
                .buttonStyle(.plain)
                .contextMenu { planMenu(plan, isCurrent: false) }
            }
        }
    }

    private func planRow(_ plan: DietPlan, isCurrent: Bool) -> some View {
        var meta: [String] = []
        // The type only when the name doesn't already say it ("Mediterranean Diet")
        if !plan.dietType.isEmpty && !plan.name.localizedCaseInsensitiveContains(plan.dietType) {
            meta.append(plan.dietType)
        }
        if let start = plan.startDate {
            meta.append("since \(start.formatted(.dateTime.month(.abbreviated).year()))")
        }

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isCurrent ? Notebook.ink : Notebook.inkSecondary)
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
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
        .accessibilityHint("Opens the diet plan editor")
    }

    @ViewBuilder
    private func planMenu(_ plan: DietPlan, isCurrent: Bool) -> some View {
        if !isCurrent {
            Button {
                DietPlan.makeCurrent(plan, among: dietPlans)
            } label: {
                Label("Make Current", image: "ph.check-circle")
            }
        }
        Button(role: .destructive) {
            planPendingDelete = plan
        } label: {
            Label("Delete", image: "ph.trash")
        }
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("ph.plus")
                    .font(.callout)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Notebook.inkSecondary)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension DietPlan {
    /// One plan is current at a time; making one current archives the rest.
    static func makeCurrent(_ plan: DietPlan, among plans: [DietPlan]) {
        for other in plans where other.id != plan.id { other.active = false }
        plan.active = true
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
    /// Foods ticked as avoided. Everything else on the list counts as eaten.
    @State private var avoided: Set<String> = []
    /// Foods saved on the plan that aren't one of the standard categories.
    @State private var customFoods: [String] = []

    @Query private var allPlans: [DietPlan]

    private var foodOptions: [String] {
        FoodCategory.allCases.map(\.rawValue) + customFoods
    }

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
                                    avoided = Set(option.defaultAvoided.map(\.rawValue))
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

                Section {
                    ForEach(foodOptions, id: \.self) { food in
                        let isAvoided = avoided.contains(food)
                        Button {
                            withAnimation(AppAnimation.quickToggle) { avoided.formSymmetricDifference([food]) }
                        } label: {
                            HStack(spacing: 12) {
                                Text(food)
                                    .foregroundStyle(Notebook.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                NotebookCheckbox(isOn: false, isCrossed: isAvoided)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(food)
                        .accessibilityValue(isAvoided ? "Avoided" : "Not avoided")
                        .accessibilityAddTraits(isAvoided ? .isSelected : [])
                    }
                } header: {
                    NotebookFormHeader("Foods I avoid")
                } footer: {
                    Text("Filled in from the diet type. Tap a food to change it.")
                        .font(.footnote)
                        .foregroundStyle(Notebook.inkSecondary)
                }

                if dietPlan != nil {
                    Section {
                        Toggle("Current plan", isOn: $active)
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
                guard let d = dietPlan else {
                    avoided = Set(selectedDietType.defaultAvoided.map(\.rawValue))
                    return
                }
                name = d.name; active = d.active; notes = d.notes
                let standard = Set(FoodCategory.allCases.map { $0.rawValue.lowercased() })
                var custom: [String] = []
                for food in d.allowedFoods + d.avoidFoods
                where !standard.contains(food.lowercased()) && !custom.contains(food) {
                    custom.append(food)
                }
                customFoods = custom
                // Stored names may differ in case from the categories ("Processed foods")
                avoided = Set(d.avoidFoods.map { food in
                    FoodCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(food) == .orderedSame }?.rawValue ?? food
                })
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
        let avoidList = foodOptions.filter { avoided.contains($0) }
        let eatList = foodOptions.filter { !avoided.contains($0) }

        let plan: DietPlan
        if let dietPlan {
            plan = dietPlan
            plan.name = name; plan.dietType = resolvedDietType
            plan.startDate = startDate; plan.endDate = hasEndDate ? endDate : nil
            plan.notes = notes
            plan.allowedFoods = eatList
            plan.avoidFoods = avoidList
            plan.active = active
        } else {
            plan = DietPlan(name: name, dietType: resolvedDietType,
                startDate: startDate, endDate: hasEndDate ? endDate : nil,
                allowedFoods: eatList, avoidFoods: avoidList, notes: notes)
            modelContext.insert(plan)
        }
        if plan.active { DietPlan.makeCurrent(plan, among: allPlans) }
        dismiss()
    }
}
