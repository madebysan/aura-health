import SwiftUI
import SwiftData

// MARK: - Tracking View (Habits + Adherence)

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Habit.gridOrder)
    private var allHabits: [Habit]

    @Query(sort: \HabitLog.date, order: .reverse)
    private var allLogs: [HabitLog]

    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var editingHabit: Habit?

    private var activeHabits: [Habit] {
        allHabits.filter(\.active)
    }

    private var groupedHabits: [(section: GridSection, habits: [Habit])] {
        let grouped = Dictionary(grouping: activeHabits, by: \.gridSection)
        return GridSection.allCases.compactMap { section in
            guard let habits = grouped[section], !habits.isEmpty else { return nil }
            return (section: section, habits: habits)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $selectedTab) {
                Text("Daily Grid").tag(0)
                Text("Adherence").tag(1)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            ScrollView {
                if selectedTab == 0 {
                    dailyGridTab
                } else {
                    adherenceTab
                }
            }
        }
        .navigationTitle("Tracking")
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

    // MARK: - Daily Grid Tab

    private var dailyGridTab: some View {
        VStack(spacing: 0) {
            if activeHabits.isEmpty {
                EmptyStateView(
                    icon: "repeat",
                    title: "No Habits",
                    message: "Create habits to start tracking your daily routines.",
                    actionLabel: "Add Habit",
                    action: { showingAddSheet = true }
                )
            } else {
                // Day columns header
                dayColumnsHeader
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Habit rows grouped by section
                VStack(spacing: 0) {
                    ForEach(groupedHabits, id: \.section) { group in
                        sectionHeader(group.section)
                        ForEach(group.habits) { habit in
                            habitRow(habit)
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    // MARK: - Day Columns

    private let dayCount = 14

    private var dayDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var dayColumnsHeader: some View {
        HStack(spacing: 0) {
            // Habit name column
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)

            // Day columns
            ForEach(dayDates, id: \.self) { date in
                let cal = Calendar.current
                let isToday = cal.isDateInToday(date)
                VStack(spacing: 2) {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary.opacity(0.6))
                        .textCase(.uppercase)
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                }
                .frame(width: 32)
            }
        }
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ section: GridSection) -> some View {
        HStack {
            Text(section.displayName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(spacing: 0) {
            // Habit name + edit button
            Button {
                editingHabit = habit
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text(habit.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Day cells
            ForEach(dayDates, id: \.self) { date in
                DayCell(habit: habit, date: date, allLogs: allLogs)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Adherence Tab

    private var adherenceTab: some View {
        VStack(spacing: 10) {
            if activeHabits.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Habits to Track",
                    message: "Add habits to see your adherence stats."
                )
            } else {
                ForEach(Array(activeHabits.enumerated()), id: \.element.id) { index, habit in
                    AdherenceRow(habit: habit)
                        .staggeredAppearance(index: index)
                }
            }
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Day Cell (Toggle)

struct DayCell: View {
    @Environment(\.modelContext) private var modelContext

    let habit: Habit
    let date: Date
    let allLogs: [HabitLog]

    @State private var justToggled = false

    private var logForDay: HabitLog? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        return habit.logs.first { cal.startOfDay(for: $0.date) == dayStart }
    }

    private var isDone: Bool {
        logForDay?.done ?? false
    }

    private var isFuture: Bool {
        Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        Button {
            guard !isFuture else { return }
            toggleDay()
        } label: {
            ZStack {
                if isFuture {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clear)
                } else if isDone {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusGreen)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                } else if logForDay != nil {
                    // Explicitly marked as not done
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.5))
                        )
                } else {
                    // No log — empty cell
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 24, height: 24)
                }
            }
            .symbolEffect(.bounce, value: justToggled)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func toggleDay() {
        justToggled.toggle()
        withAnimation(AppAnimation.quickToggle) {
            if let log = logForDay {
                if log.done {
                    // done -> not done
                    log.done = false
                } else {
                    // not done -> remove log (back to empty)
                    modelContext.delete(log)
                }
            } else {
                // no log -> done
                let log = HabitLog(date: date, habit: habit, done: true)
                modelContext.insert(log)
            }
        }
    }
}

// MARK: - Adherence Row

struct AdherenceRow: View {
    let habit: Habit

    private var adherenceRate: Double {
        let logs = habit.logs
        guard !logs.isEmpty else { return 0 }
        return Double(logs.filter(\.done).count) / Double(logs.count) * 100
    }

    private var streak: Int {
        var count = 0
        for log in habit.logs.sorted(by: { $0.date > $1.date }) {
            if log.done { count += 1 } else { break }
        }
        return count
    }

    private var rateColor: Color {
        adherenceRate >= 80 ? AppColors.statusGreen : adherenceRate >= 50 ? AppColors.statusOrange : AppColors.statusRed
    }

    private var heatmapData: [Date: Bool] {
        var map: [Date: Bool] = [:]
        for log in habit.logs {
            map[Calendar.current.startOfDay(for: log.date)] = log.done
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(habit.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("\(streak)d")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text("\(Int(adherenceRate))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(rateColor)
                }
            }

            // Mini heatmap
            HeatmapView(data: heatmapData, months: 3)
                .frame(height: 50)
                .clipped()
        }
        .cardStyle(padding: 14, cornerRadius: 12)
        .hoverCard()
    }
}

// MARK: - Habit Form

struct HabitFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var habit: Habit?

    @State private var name = ""
    @State private var category: HabitCategory = .lifestyle
    @State private var gridSection: GridSection = .morning
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
                    Picker("Time of Day", selection: $gridSection) {
                        ForEach(GridSection.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Toggle("Active", isOn: $active)
                    }
                }
            }
            .formStyle(.grouped)
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
                name = habit.name
                category = habit.category
                gridSection = habit.gridSection
                active = habit.active
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func save() {
        if let habit {
            habit.name = name
            habit.category = category
            habit.gridSection = gridSection
            habit.active = active
        } else {
            modelContext.insert(Habit(
                name: name,
                category: category,
                gridSection: gridSection
            ))
        }
        dismiss()
    }
}
