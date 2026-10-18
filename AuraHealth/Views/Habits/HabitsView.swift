import SwiftUI
import SwiftData

// MARK: - Habit day helpers

extension Habit {
    /// The log for a calendar day, if any.
    func log(on day: Date) -> HabitLog? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        return (logs ?? []).first { cal.startOfDay(for: $0.date) == start }
    }

    /// Consecutive done days ending today, or ending yesterday when today has
    /// no entry yet (so an unlogged morning doesn't reset the streak).
    var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if log(on: day) == nil { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while let entry = log(on: day), entry.done {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Share of the last `days` days (before today) marked done, 0–100.
    func doneRate(lastDays days: Int) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let done = (1...days).filter { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return false }
            return log(on: day)?.done == true
        }.count
        return Int((Double(done) / Double(days) * 100).rounded())
    }
}

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
    /// Tracks the last habit toggled so sensory feedback fires on each new tap (iOS only).
    @State private var lastToggledHabitID: UUID?
    @State private var draggingHabit: Habit?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledDayColumnWidth: CGFloat = 44

    /// Day columns are 44 pt touch targets that grow with text size up to a cap
    /// so five days always fit.
    private var dayColumnWidth: CGFloat { min(scaledDayColumnWidth, 52) }

    private var activeHabits: [Habit] {
        allHabits.filter(\.active)
    }

    private var allActiveSections: [GridSection] {
        let grouped = Dictionary(grouping: activeHabits, by: \.gridSection)
        return GridSection.allCases.filter { grouped[$0]?.isEmpty == false }
    }

    private var doneTodayCount: Int {
        activeHabits.filter { $0.log(on: Date())?.done == true }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(doneTodayCount) of \(activeHabits.count) done today")
                    .kicker()
                    .padding(.bottom, 10)

                UnderlineTabs(options: [0, 1], selection: $selectedTab) { $0 == 0 ? "Daily" : "Adherence" }

                if selectedTab == 0 {
                    dailyGridTab
                } else {
                    adherenceTab
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Habit")
            }
        }
        // Sensory feedback fires whenever a habit is toggled (iOS 17+).
        .sensoryFeedback(.impact(flexibility: .solid), trigger: lastToggledHabitID)
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
                    action: { showingAddSheet = true },
                    chatHint: "Try \"Add a morning meditation habit\" in Chat"
                )
            } else {
                // Day columns header
                dayColumnsHeader

                // Habit rows grouped by section with drag and drop.
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
                            }
                        }
                    }
                }
            }
        }
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
                .accessibilityHidden(true)

            // Day columns
            ForEach(dayDates, id: \.self) { date in
                let cal = Calendar.current
                let isToday = cal.isDateInToday(date)
                VStack(spacing: 2) {
                    Text(String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(2)))
                        .font(Notebook.mono(.caption2, weight: isToday ? .semibold : .regular))
                        .textCase(.uppercase)
                    Text("\(cal.component(.day, from: date))")
                        .font(Notebook.mono(.footnote, weight: isToday ? .semibold : .regular))
                        .overlay(alignment: .bottom) {
                            if isToday { Rectangle().fill(Notebook.ink).frame(height: 2).offset(y: 3) }
                        }
                }
                .foregroundStyle(isToday ? Notebook.ink : Notebook.inkTertiary)
                #if os(macOS)
                .frame(width: 32)
                #else
                .frame(width: dayColumnWidth)
                #endif
                .accessibilityElement(children: .combine)
                // Grid chrome stops growing at the largest standard size
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .padding(.vertical, 12)
        .ruled()
    }

    private func sectionHeader(_ section: GridSection) -> some View {
        let habits = activeHabits.filter { $0.gridSection == section }
        let done = habits.filter { $0.log(on: Date())?.done == true }.count
        return HStack(alignment: .firstTextBaseline) {
            Text(section.displayName).kicker()
            Spacer()
            Text("\(done)/\(habits.count) today").kicker()
        }
        .padding(.top, 22)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func habitRow(_ habit: Habit) -> some View {
        // At accessibility text sizes the name gets its own line instead of truncating
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 0))

        return layout {
            // Habit name + edit affordance
            Button {
                editingHabit = habit
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Notebook.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text((habit.trackingType == .quantity && !habit.unit.isEmpty ? "\(habit.unit) · " : "") + "streak \(habit.currentStreak)d")
                        .font(Notebook.mono(.caption2))
                        .foregroundStyle(Notebook.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(habit.name)")

            // Day cells
            HStack(spacing: 0) {
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
                    .frame(width: dayColumnWidth, height: dayColumnWidth)
                    #endif
                    .opacity(isToday ? 1.0 : 0.62)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .ruled()
        .contentShape(Rectangle())
    }

    // MARK: - Adherence Tab

    private var adherenceTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeHabits.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Habits to Track",
                    message: "Add habits to see your adherence stats."
                )
            } else {
                let rates = activeHabits.map { (habit: $0, rate: $0.doneRate(lastDays: 30)) }.sorted { $0.rate > $1.rate }
                let overall = rates.isEmpty ? 0 : rates.map(\.rate).reduce(0, +) / rates.count
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 30 days").kicker()
                    BigNumber(value: "\(overall)", suffix: "% overall")
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled()

                ForEach(Array(rates.enumerated()), id: \.element.habit.id) { index, item in
                    AdherenceRow(habit: item.habit, rate: item.rate)
                        .staggeredAppearance(index: index)
                }
            }
        }
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
    @ScaledMetric(relativeTo: .subheadline) private var squareSize: CGFloat = 28

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

    @ScaledMetric(relativeTo: .subheadline) private var scaledBox: CGFloat = 22
    @State private var popScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var boxSize: CGFloat { min(scaledBox, 30) }

    var body: some View {
        Button {
            guard !isFuture else { return }
            toggleDay()
        } label: {
            ZStack {
                if !isFuture {
                    Rectangle()
                        .fill(isDone ? Notebook.ink : Color.clear)
                        .overlay(Rectangle().stroke(isDone ? Notebook.ink : Notebook.emptyBox, lineWidth: 1.5))
                        .overlay {
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Notebook.paper)
                            } else if logForDay != nil {
                                // Explicitly marked as not done: a slash, like a crossed box
                                Path { p in
                                    p.move(to: CGPoint(x: boxSize * 0.22, y: boxSize * 0.78))
                                    p.addLine(to: CGPoint(x: boxSize * 0.78, y: boxSize * 0.22))
                                }
                                .stroke(Notebook.inkTertiary, lineWidth: 1.5)
                            }
                        }
                        .frame(width: boxSize, height: boxSize)
                        .scaleEffect(popScale)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15), value: isDone)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel("\(habit.name), \(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
        .accessibilityValue(accessibilityState)
        .accessibilityHint(isFuture ? "" : "Changes this day's entry")
    }

    private var accessibilityState: String {
        if isDone { return "Done" }
        if logForDay != nil { return "Not done" }
        return "No entry"
    }

    private func toggleDay() {
        justToggled.toggle()
        onToggle?()
        let becomesDone = logForDay == nil
        if becomesDone && !reduceMotion {
            // Small press-in and spring back when a day is checked off
            withAnimation(.easeOut(duration: 0.1)) { popScale = 0.82 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { popScale = 1 }
            }
        }
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
    let rate: Int

    /// The last 30 days before today, oldest first.
    private var days: [(date: Date, log: HabitLog?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (1...30).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { ($0, habit.log(on: $0)) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(habit.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                Spacer()
                Text("\(rate)%")
                    .font(Notebook.mono(.title3, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Notebook.ink)
            }
            Text("last 30 days · streak \(habit.currentStreak)d")
                .font(Notebook.mono(.caption))
                .foregroundStyle(Notebook.inkSecondary)

            // One square per day: filled done, outlined missed, faint when not logged
            HStack(spacing: 2) {
                ForEach(days, id: \.date) { day in
                    Rectangle()
                        .fill(day.log?.done == true ? Notebook.ink : Color.clear)
                        .overlay(Rectangle().stroke(day.log == nil ? Notebook.track : (day.log!.done ? Notebook.ink : Notebook.emptyBox), lineWidth: 1))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
        .ruled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name), \(rate) percent over the last 30 days, streak \(habit.currentStreak) days")
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
            NotebookForm {
                Section {
                    NotebookField("Name", text: $name, prompt: "e.g. Morning walk")
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
