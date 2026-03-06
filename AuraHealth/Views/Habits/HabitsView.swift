import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Habit.gridOrder)
    private var habits: [Habit]

    @Query(sort: \HabitLog.date, order: .reverse)
    private var habitLogs: [HabitLog]

    @State private var categoryFilter: HabitCategory?
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var editingHabit: Habit?

    private var filteredHabits: [Habit] {
        habits.filter { habit in
            let matchesCategory = categoryFilter == nil || habit.category == categoryFilter
            let matchesActive = showArchived || habit.active
            return matchesCategory && matchesActive
        }
    }

    private var activeHabits: [Habit] {
        habits.filter(\.active)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Daily action grid
                if !activeHabits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Today")

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220))], spacing: 8) {
                            ForEach(Array(activeHabits.enumerated()), id: \.element.id) { index, habit in
                                DailyHabitToggle(habit: habit, logs: habitLogs)
                                    .staggeredAppearance(index: index)
                            }
                        }
                    }
                    .cardStyle()
                }

                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterPill(label: "All", isActive: categoryFilter == nil) {
                            withAnimation(AppAnimation.viewSwitch) { categoryFilter = nil }
                        }
                        ForEach(HabitCategory.allCases, id: \.self) { cat in
                            FilterPill(label: cat.displayName, isActive: categoryFilter == cat) {
                                withAnimation(AppAnimation.viewSwitch) { categoryFilter = cat }
                            }
                        }
                        Divider().frame(height: 20)
                        Toggle("Archived", isOn: $showArchived)
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }

                // Habit cards
                if filteredHabits.isEmpty {
                    EmptyStateView(
                        icon: "repeat",
                        title: "No Habits",
                        message: "Create habits to build your daily routines.",
                        actionLabel: "Add Habit",
                        action: { showingAddSheet = true }
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400))], spacing: 10) {
                        ForEach(Array(filteredHabits.enumerated()), id: \.element.id) { index, habit in
                            HabitCard(habit: habit)
                                .onTapGesture { editingHabit = habit }
                                .staggeredAppearance(index: index)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            HabitFormSheet()
        }
        .sheet(item: $editingHabit) { habit in
            HabitFormSheet(habit: habit)
        }
    }
}

// MARK: - Daily Toggle

struct DailyHabitToggle: View {
    @Environment(\.modelContext) private var modelContext

    let habit: Habit
    let logs: [HabitLog]

    @State private var justToggled = false

    private var todayLog: HabitLog? {
        let today = Calendar.current.startOfDay(for: Date())
        return habit.logs.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private var isDone: Bool { todayLog?.done ?? false }

    var body: some View {
        Button { toggleToday() } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.4))
                    .symbolEffect(.bounce, value: justToggled)

                Text(habit.name)
                    .font(.subheadline.weight(isDone ? .medium : .regular))
                    .foregroundStyle(isDone ? .primary : .secondary)
                    .lineLimit(1)
                    .strikethrough(isDone, color: .secondary.opacity(0.3))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isDone ? AppColors.statusGreen.opacity(0.08) : Color.primary.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func toggleToday() {
        justToggled.toggle()
        withAnimation(AppAnimation.quickToggle) {
            if let log = todayLog {
                log.done.toggle()
            } else {
                let log = HabitLog(date: Date(), habit: habit, done: true)
                modelContext.insert(log)
            }
        }
    }
}

// MARK: - Habit Card

struct HabitCard: View {
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(habit.name)
                    .font(.headline)
                Spacer()
                StatusBadge(label: habit.category.displayName, color: categoryColor)
            }

            HStack(spacing: 12) {
                Label(habit.frequency, systemImage: "calendar")
                if habit.trackingType == .quantity, !habit.unit.isEmpty {
                    Label(habit.unit, systemImage: "number")
                }
                if !habit.active {
                    StatusBadge(label: "Archived", color: .orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle(padding: 14, cornerRadius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .hoverCard()
    }

    private var categoryColor: Color {
        switch habit.category {
        case .lifestyle: .blue
        case .therapy: .purple
        case .diet: .green
        case .exercise: .orange
        }
    }
}

// MARK: - Habit Form

struct HabitFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var habit: Habit?

    @State private var name = ""
    @State private var category: HabitCategory = .lifestyle
    @State private var trackingType: TrackingType = .boolean
    @State private var frequency = "daily"
    @State private var unit = ""
    @State private var active = true

    var isEditing: Bool { habit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                }

                Section {
                    Picker("Tracking", selection: $trackingType) {
                        Text("Done / Skip").tag(TrackingType.boolean)
                        Text("Quantity").tag(TrackingType.quantity)
                    }
                    if trackingType == .quantity {
                        TextField("Unit (cups, mins, etc.)", text: $unit)
                    }
                    TextField("Frequency", text: $frequency)
                }

                if isEditing {
                    Section {
                        Toggle("Active", isOn: $active)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Habit" : "Add Habit")
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
                guard let habit else { return }
                name = habit.name; category = habit.category
                trackingType = habit.trackingType; frequency = habit.frequency
                unit = habit.unit; active = habit.active
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func save() {
        if let habit {
            habit.name = name; habit.category = category
            habit.trackingType = trackingType; habit.frequency = frequency
            habit.unit = unit; habit.active = active
        } else {
            modelContext.insert(Habit(name: name, category: category,
                trackingType: trackingType, frequency: frequency, unit: unit))
        }
        dismiss()
    }
}
