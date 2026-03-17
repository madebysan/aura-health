import SwiftUI
import SwiftData

// MARK: - Tracking View (Habits + Adherence)

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DailyProtocolService.self) private var dailyProtocolService

    @Query(sort: \Habit.gridOrder)
    private var allHabits: [Habit]

    @Query(sort: \HabitLog.date, order: .reverse)
    private var allLogs: [HabitLog]

    @Query(sort: \SmartHabit.priority)
    private var allSmartHabits: [SmartHabit]

    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var editingHabit: Habit?
    /// Tracks the last habit toggled so sensory feedback fires on each new tap (iOS only).
    @State private var lastToggledHabitID: UUID?
    /// Whether a refresh is in progress for pull-to-refresh (iOS only).
    @State private var isRefreshing = false
    @State private var expandedSmartHabitID: UUID?
    @State private var draggingHabit: Habit?

    private var activeHabits: [Habit] {
        allHabits.filter(\.active)
    }

    /// Today's AI-generated smart habits (not dismissed).
    private var todaySmartHabits: [SmartHabit] {
        let today = Calendar.current.startOfDay(for: Date())
        return allSmartHabits.filter { $0.date == today && !$0.dismissed }
    }

    /// Smart habits grouped by grid section for merging into the daily grid.
    private var smartHabitsBySection: [GridSection: [SmartHabit]] {
        Dictionary(grouping: todaySmartHabits, by: \.gridSection)
    }

    private var groupedHabits: [(section: GridSection, habits: [Habit])] {
        let grouped = Dictionary(grouping: activeHabits, by: \.gridSection)
        return GridSection.allCases.compactMap { section in
            guard let habits = grouped[section], !habits.isEmpty else { return nil }
            return (section: section, habits: habits)
        }
    }

    /// All sections that have either manual or smart habits.
    private var allActiveSections: [GridSection] {
        let manualGrouped = Dictionary(grouping: activeHabits, by: \.gridSection)
        return GridSection.allCases.filter { section in
            (manualGrouped[section] != nil && !manualGrouped[section]!.isEmpty) ||
            (smartHabitsBySection[section] != nil && !smartHabitsBySection[section]!.isEmpty)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PillSegmentedPicker(
                options: [0, 1],
                selection: $selectedTab,
                label: { $0 == 0 ? "Daily Grid" : "Adherence" }
            )
            .padding()

            ScrollView {
                if selectedTab == 0 {
                    dailyGridTab
                } else {
                    adherenceTab
                }
            }
            #if os(iOS)
            // Pull-to-refresh: re-queries SwiftData automatically on next runloop tick.
            .refreshable {
                await dailyProtocolService.regenerate(context: modelContext)
            }
            #endif
        }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await dailyProtocolService.generateIfNeeded(context: modelContext)
            dailyProtocolService.cleanupOldProtocols(context: modelContext)
        }
        #if os(iOS)
        // Sensory feedback fires whenever a habit is toggled (iOS 17+).
        .sensoryFeedback(.impact(flexibility: .solid), trigger: lastToggledHabitID)
        #endif
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
            // Smart habits generating indicator
            if dailyProtocolService.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating today's smart habits...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if activeHabits.isEmpty && todaySmartHabits.isEmpty {
                EmptyStateView(
                    icon: "repeat",
                    title: "No Habits",
                    message: "Create habits to start tracking your daily routines.",
                    actionLabel: "Add Habit",
                    action: { showingAddSheet = true },
                    chatHint: "Try \"Add a morning meditation habit\" in Chat"
                )
            } else {
                // Day columns header
                dayColumnsHeader
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Habit rows grouped by section (manual + smart) — with drag & drop
                let manualGrouped = Dictionary(grouping: activeHabits, by: \.gridSection)
                VStack(spacing: 0) {
                    ForEach(allActiveSections, id: \.self) { section in
                        sectionHeader(section)
                            .dropDestination(for: String.self) { items, _ in
                                guard let idString = items.first,
                                      let habit = activeHabits.first(where: { $0.id.uuidString == idString }) else { return false }
                                habit.gridSection = section
                                habit.gridOrder = 0
                                // Push existing habits down
                                let existing = (manualGrouped[section] ?? []).filter { $0.id != habit.id }
                                for (i, h) in existing.enumerated() { h.gridOrder = i + 1 }
                                return true
                            }

                        // Manual habits for this section
                        if let habits = manualGrouped[section] {
                            ForEach(habits) { habit in
                                habitRow(habit)
                                    .draggable(habit.id.uuidString) {
                                        Text(habit.name)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let idString = items.first,
                                              let source = activeHabits.first(where: { $0.id.uuidString == idString }) else { return false }
                                        moveHabit(source, to: habit)
                                        return true
                                    }
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }

                        // Smart habits for this section
                        if let smartHabits = smartHabitsBySection[section] {
                            ForEach(smartHabits) { smartHabit in
                                smartHabitRow(smartHabit)
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            if let error = dailyProtocolService.lastError {
                InlineErrorBanner(message: error)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    // MARK: - Drag & Drop

    /// Move a dragged habit to the position of a target habit (same or different section).
    private func moveHabit(_ source: Habit, to target: Habit) {
        let targetSection = target.gridSection
        source.gridSection = targetSection

        // Rebuild order for the target section
        let manualGrouped = Dictionary(grouping: activeHabits, by: \.gridSection)
        var sectionHabits = (manualGrouped[targetSection] ?? []).filter { $0.id != source.id }

        if let targetIndex = sectionHabits.firstIndex(where: { $0.id == target.id }) {
            sectionHabits.insert(source, at: targetIndex)
        } else {
            sectionHabits.append(source)
        }

        for (index, habit) in sectionHabits.enumerated() {
            habit.gridOrder = index
        }
    }

    // MARK: - Day Columns

    #if os(macOS)
    private let dayCount = 14
    #else
    private let dayCount = 5
    #endif

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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary.opacity(0.6))
                        .textCase(.uppercase)
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                }
                #if os(macOS)
                .frame(width: 32)
                #else
                .frame(width: 36)
                #endif
                .opacity(isToday ? 1.0 : 0.5)
            }
        }
        .padding(.vertical, 10)
    }

    /// Returns the SF Symbol name for a time-of-day section.
    private func iconName(for section: GridSection) -> String {
        switch section {
        case .any:       "clock.fill"
        case .morning:   "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening:   "sunset.fill"
        case .night:     "moon.stars.fill"
        }
    }

    /// Returns the accent color for a time-of-day section.
    private func iconColor(for section: GridSection) -> Color {
        switch section {
        case .any:       .gray
        case .morning:   .orange
        case .afternoon: .yellow
        case .evening:   .pink
        case .night:     .indigo
        }
    }

    private func sectionHeader(_ section: GridSection) -> some View {
        HStack(spacing: 6) {
            // Section icon gives a quick visual cue of the time of day.
            Image(systemName: iconName(for: section))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor(for: section))
            Text(section.displayName.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func smartHabitRow(_ smartHabit: SmartHabit) -> some View {
        HStack(spacing: 0) {
            // Smart habit name + sparkle indicator
            Button {
                withAnimation(AppAnimation.expand) {
                    expandedSmartHabitID = expandedSmartHabitID == smartHabit.id ? nil : smartHabit.id
                }
            } label: {
                VStack(alignment: .leading, spacing: expandedSmartHabitID == smartHabit.id ? 4 : 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        Text(smartHabit.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(expandedSmartHabitID == smartHabit.id ? 3 : 1)
                    }
                    if expandedSmartHabitID == smartHabit.id && !smartHabit.reason.isEmpty {
                        Text(smartHabit.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Today-only toggle
            SmartHabitDayCell(smartHabit: smartHabit, onToggle: {
                #if os(iOS)
                lastToggledHabitID = smartHabit.id
                #endif
            })
            #if os(macOS)
            .frame(width: 32, height: 32)
            #else
            .frame(width: 36, height: 36)
            #endif

            // Dismiss button
            Button {
                withAnimation(AppAnimation.quickToggle) {
                    smartHabit.dismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(spacing: 0) {
            // Habit name + edit affordance
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
                let isToday = Calendar.current.isDateInToday(date)
                DayCell(
                    habit: habit,
                    date: date,
                    allLogs: allLogs,
                    onToggle: {
                        #if os(iOS)
                        lastToggledHabitID = habit.id
                        #endif
                    }
                )
                #if os(macOS)
                .frame(width: 32, height: 32)
                #else
                .frame(width: 36, height: 36)
                #endif
                .opacity(isToday ? 1.0 : 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
    /// Called after every toggle so the parent can fire haptics / update state.
    var onToggle: (() -> Void)? = nil

    @State private var justToggled = false

    private var logForDay: HabitLog? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        return (habit.logs ?? []).first { cal.startOfDay(for: $0.date) == dayStart }
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
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                } else if logForDay != nil {
                    // Explicitly marked as not done
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.5))
                        )
                } else {
                    // No log — empty cell
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 28, height: 28)
                }
            }
            .symbolEffect(.bounce, value: justToggled)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func toggleDay() {
        justToggled.toggle()
        onToggle?()
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

// MARK: - Smart Habit Day Cell (Today Only)

struct SmartHabitDayCell: View {
    let smartHabit: SmartHabit
    var onToggle: (() -> Void)? = nil

    @State private var justToggled = false

    var body: some View {
        Button {
            justToggled.toggle()
            onToggle?()
            withAnimation(AppAnimation.quickToggle) {
                smartHabit.done.toggle()
            }
        } label: {
            ZStack {
                if smartHabit.done {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.08))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .symbolEffect(.bounce, value: justToggled)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adherence Row

struct AdherenceRow: View {
    let habit: Habit

    private var adherenceRate: Double {
        let logs = habit.logs ?? []
        guard !logs.isEmpty else { return 0 }
        return Double(logs.filter(\.done).count) / Double(logs.count) * 100
    }

    private var streak: Int {
        let cal = Calendar.current
        let sortedLogs = (habit.logs ?? []).sorted(by: { $0.date > $1.date })
        var count = 0
        var expectedDay = cal.startOfDay(for: Date())
        for log in sortedLogs {
            let logDay = cal.startOfDay(for: log.date)
            // Skip future logs
            if logDay > expectedDay { continue }
            // Skip days without logs (gap breaks streak)
            if logDay < expectedDay { break }
            if log.done {
                count += 1
                expectedDay = cal.date(byAdding: .day, value: -1, to: expectedDay)!
            } else {
                break
            }
        }
        return count
    }

    private var rateColor: Color {
        adherenceRate >= 80 ? AppColors.statusGreen : adherenceRate >= 50 ? AppColors.statusOrange : AppColors.statusRed
    }

    private var heatmapData: [Date: Bool] {
        var map: [Date: Bool] = [:]
        for log in habit.logs ?? [] {
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

            // Mini heatmap (60 days)
            HeatmapView(data: heatmapData, months: 2)
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
