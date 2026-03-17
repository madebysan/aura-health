import SwiftUI
import SwiftData

struct ConditionsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Condition.name)
    private var conditions: [Condition]

    @State private var showingAddCondition = false
    @State private var editingCondition: Condition?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if conditions.isEmpty {
                    EmptyStateView(
                        icon: "stethoscope",
                        title: "No Conditions",
                        message: "Track your health conditions and their status.",
                        actionLabel: "Add Condition",
                        action: { showingAddCondition = true },
                        chatHint: "Try \"I have seasonal allergies, managed\" in Chat"
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

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.quaternary)
                        }
                        .cardStyle(padding: 12, cornerRadius: 10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture { editingCondition = condition }
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(condition)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .hoverCard()
                        .staggeredAppearance(index: index)
                    }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("Conditions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddCondition = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCondition) { ConditionFormSheet() }
        .sheet(item: $editingCondition) { ConditionFormSheet(condition: $0) }
    }

    private func conditionColor(_ status: ConditionStatus) -> Color {
        switch status {
        case .active: AppColors.statusRed
        case .managed: AppColors.statusOrange
        case .resolved: AppColors.statusGreen
        }
    }
}

// MARK: - Diet Plans View (standalone)

struct DietPlansView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DietPlan.name)
    private var dietPlans: [DietPlan]

    @State private var showingAddDiet = false
    @State private var editingDiet: DietPlan?

    private var activePlan: DietPlan? {
        dietPlans.first { $0.active }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if dietPlans.isEmpty {
                    EmptyStateView(
                        icon: "fork.knife",
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
                            foodSection(title: "Approved", foods: approved, color: .green, plan: plan, isApproved: true)
                                .staggeredAppearance(index: 1)
                        }

                        if !avoided.isEmpty {
                            foodSection(title: "Avoided", foods: avoided, color: .red, plan: plan, isApproved: false)
                                .staggeredAppearance(index: 2)
                        }
                    }

                    // Other plans
                    let otherPlans = dietPlans.filter { !$0.active }
                    if !otherPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other Plans")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(otherPlans) { plan in
                                planRow(plan)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("Diet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddDiet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddDiet) { DietPlanFormSheet() }
        .sheet(item: $editingDiet) { DietPlanFormSheet(dietPlan: $0) }
    }

    // MARK: - Active Plan Header

    private func activePlanHeader(_ plan: DietPlan) -> some View {
        HStack(spacing: 12) {
            let dietOption = DietTypeOption.from(plan.dietType)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let option = dietOption {
                        Image(systemName: option.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(option.color)
                    }
                    Text(plan.name)
                        .font(.headline)
                }
                if !plan.dietType.isEmpty {
                    Text(plan.dietType)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                editingDiet = plan
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(AppAnimation.quickToggle) {
                    modelContext.delete(plan)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - Food Section

    private func foodSection(title: String, foods: [String], color: Color, plan: DietPlan, isApproved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(foods.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(foods, id: \.self) { food in
                    let category = FoodCategory(rawValue: food)
                    Button {
                        withAnimation(AppAnimation.quickToggle) {
                            toggleFood(food, plan: plan, currentlyApproved: isApproved)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category?.iconName ?? "circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isApproved ? color : .secondary)
                                .frame(width: 18)

                            Text(food)
                                .font(.subheadline)
                                .foregroundStyle(isApproved ? .primary : .secondary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: isApproved ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(isApproved ? color.opacity(0.6) : Color.red.opacity(0.4))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isApproved ? color.opacity(0.06) : Color.primary.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isApproved ? color.opacity(0.12) : Color.primary.opacity(0.04), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isApproved ? "Tap to move to Avoided" : "Tap to move to Approved")
                }
            }
        }
        .cardStyle()
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
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name).font(.subheadline.weight(.medium))
                if !plan.dietType.isEmpty {
                    Text(plan.dietType).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(label: "Archived", color: .secondary)
        }
        .cardStyle(padding: 12, cornerRadius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { editingDiet = plan }
        .contextMenu {
            Button {
                plan.active = true
            } label: {
                Label("Set as Active", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                modelContext.delete(plan)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .hoverCard()
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
            Form {
                if isEditing || isCustom {
                    // Edit mode or custom: show text field
                    Section {
                        TextField("Condition Name", text: $name)
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
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
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
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            withAnimation(AppAnimation.quickToggle) {
                                isCustom = true
                                name = searchText
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text("Custom condition")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .formStyle(.grouped)
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
            Form {
                Section {
                    TextField("Plan Name", text: $name)
                }

                Section("Diet Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(DietTypeOption.allCases) { option in
                            let isSelected = selectedDietType == option
                            Button {
                                withAnimation(AppAnimation.quickToggle) {
                                    selectedDietType = option
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: option.iconName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : option.color)
                                    Text(option.rawValue)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    isSelected ? option.color : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
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

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .formStyle(.grouped)
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
