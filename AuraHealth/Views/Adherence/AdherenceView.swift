import SwiftUI
import SwiftData

struct AdherenceView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Medication> { $0.active }, sort: \Medication.name)
    private var medications: [Medication]

    @Query(filter: #Predicate<Habit> { $0.active }, sort: \Habit.name)
    private var habits: [Habit]

    @State private var searchText = ""
    @State private var selectedMedication: Medication?
    @State private var selectedHabit: Habit?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if medications.isEmpty && habits.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "No Items to Track",
                        message: "Add medications or habits to start tracking adherence."
                    )
                } else {
                    if !filteredMedications.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Medications")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 500))], spacing: 12) {
                                ForEach(Array(filteredMedications.enumerated()), id: \.element.id) { index, med in
                                    AdherenceCard(
                                        name: med.name,
                                        subtitle: "\(med.dosage) \u{00B7} \(med.timing.displayName)",
                                        icon: "pills.fill",
                                        iconColor: .blue,
                                        adherenceRate: medicationAdherence(for: med),
                                        streak: medicationStreak(for: med),
                                        heatmapData: medicationHeatmap(for: med)
                                    )
                                    .onTapGesture { selectedMedication = med }
                                    .staggeredAppearance(index: index)
                                }
                            }
                        }
                    }

                    if !filteredHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Habits")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 500))], spacing: 12) {
                                ForEach(Array(filteredHabits.enumerated()), id: \.element.id) { index, habit in
                                    AdherenceCard(
                                        name: habit.name,
                                        subtitle: habit.category.displayName,
                                        icon: "repeat",
                                        iconColor: .orange,
                                        adherenceRate: habitAdherence(for: habit),
                                        streak: habitStreak(for: habit),
                                        heatmapData: habitHeatmap(for: habit)
                                    )
                                    .onTapGesture { selectedHabit = habit }
                                    .staggeredAppearance(index: index + filteredMedications.count)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .searchable(text: $searchText, prompt: "Search")
        .navigationTitle("Adherence")
        .sheet(item: $selectedMedication) { med in
            AdherenceDetailSheet(
                name: med.name,
                subtitle: "\(med.dosage) \u{00B7} \(med.timing.displayName)",
                icon: "pills.fill",
                iconColor: .blue,
                adherenceRate: medicationAdherence(for: med),
                streak: medicationStreak(for: med),
                heatmapData: medicationHeatmap(for: med),
                logs: med.logs.sorted { $0.date > $1.date }.map { ($0.date, $0.taken) }
            )
        }
        .sheet(item: $selectedHabit) { habit in
            AdherenceDetailSheet(
                name: habit.name,
                subtitle: habit.category.displayName,
                icon: "repeat",
                iconColor: .orange,
                adherenceRate: habitAdherence(for: habit),
                streak: habitStreak(for: habit),
                heatmapData: habitHeatmap(for: habit),
                logs: habit.logs.sorted { $0.date > $1.date }.map { ($0.date, $0.done) }
            )
        }
    }

    private var filteredMedications: [Medication] {
        guard !searchText.isEmpty else { return Array(medications) }
        return medications.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredHabits: [Habit] {
        guard !searchText.isEmpty else { return Array(habits) }
        return habits.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func medicationAdherence(for med: Medication) -> Double {
        let logs = med.logs
        guard !logs.isEmpty else { return 0 }
        return Double(logs.filter(\.taken).count) / Double(logs.count) * 100
    }

    private func medicationStreak(for med: Medication) -> Int {
        var streak = 0
        for log in med.logs.sorted(by: { $0.date > $1.date }) {
            if log.taken { streak += 1 } else { break }
        }
        return streak
    }

    private func medicationHeatmap(for med: Medication) -> [Date: Bool] {
        var map: [Date: Bool] = [:]
        for log in med.logs {
            map[Calendar.current.startOfDay(for: log.date)] = log.taken
        }
        return map
    }

    private func habitAdherence(for habit: Habit) -> Double {
        let logs = habit.logs
        guard !logs.isEmpty else { return 0 }
        return Double(logs.filter(\.done).count) / Double(logs.count) * 100
    }

    private func habitStreak(for habit: Habit) -> Int {
        var streak = 0
        for log in habit.logs.sorted(by: { $0.date > $1.date }) {
            if log.done { streak += 1 } else { break }
        }
        return streak
    }

    private func habitHeatmap(for habit: Habit) -> [Date: Bool] {
        var map: [Date: Bool] = [:]
        for log in habit.logs {
            map[Calendar.current.startOfDay(for: log.date)] = log.done
        }
        return map
    }
}

// MARK: - Adherence Card

struct AdherenceCard: View {
    let name: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let adherenceRate: Double
    let streak: Int
    let heatmapData: [Date: Bool]

    private var rateColor: Color {
        adherenceRate >= 80 ? AppColors.statusGreen : adherenceRate >= 50 ? AppColors.statusOrange : AppColors.statusRed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(adherenceRate))%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(rateColor)
                        .contentTransition(.numericText())
                    Text("adherence")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }

            // Heatmap
            HeatmapView(data: heatmapData, months: 6)
                .frame(height: 60)

            // Day-of-week distribution
            DayOfWeekDistribution(data: heatmapData)
                .frame(height: 40)

            // Footer stats
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(streak)d streak")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(heatmapData.count) days tracked")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .cardStyle()
        .hoverCard()
    }
}

// MARK: - Heatmap View

struct HeatmapView: View {
    let data: [Date: Bool]
    let months: Int

    private var calendar: Calendar { Calendar.current }

    private var days: [Date] {
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .month, value: -months, to: end) else { return [] }
        var current = start
        var result: [Date] = []
        while current <= end {
            result.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    var body: some View {
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(7), spacing: 2), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForDay(day))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func colorForDay(_ day: Date) -> Color {
        guard let done = data[day] else { return Color.primary.opacity(0.04) }
        return done ? AppColors.statusGreen.opacity(0.7) : AppColors.statusRed.opacity(0.35)
    }
}

// MARK: - Day of Week Distribution

struct DayOfWeekDistribution: View {
    let data: [Date: Bool]

    private var distribution: [(day: String, done: Int, missed: Int)] {
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols
        var counts: [(done: Int, missed: Int)] = Array(repeating: (0, 0), count: 7)

        for (date, done) in data {
            let weekday = cal.component(.weekday, from: date) - 1
            if done {
                counts[weekday].done += 1
            } else {
                counts[weekday].missed += 1
            }
        }

        return (0..<7).map { (day: symbols[$0], done: counts[$0].done, missed: counts[$0].missed) }
    }

    private var maxCount: Int {
        distribution.map { $0.done + $0.missed }.max() ?? 1
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(distribution, id: \.day) { item in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let total = item.done + item.missed
                        let height = geo.size.height
                        let fillHeight = maxCount > 0 ? height * CGFloat(total) / CGFloat(maxCount) : 0
                        let doneHeight = total > 0 ? fillHeight * CGFloat(item.done) / CGFloat(total) : 0

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.statusRed.opacity(0.35))
                                .frame(height: fillHeight - doneHeight)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.statusGreen.opacity(0.7))
                                .frame(height: doneHeight)
                        }
                    }
                    Text(item.day)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }
}

// MARK: - Adherence Detail Sheet

struct AdherenceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let name: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let adherenceRate: Double
    let streak: Int
    let heatmapData: [Date: Bool]
    let logs: [(date: Date, done: Bool)]

    private var rateColor: Color {
        adherenceRate >= 80 ? AppColors.statusGreen : adherenceRate >= 50 ? AppColors.statusOrange : AppColors.statusRed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header stats
                    HStack(spacing: 24) {
                        VStack(spacing: 4) {
                            Text("\(Int(adherenceRate))%")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(rateColor)
                            Text("Adherence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 4) {
                            Text("\(streak)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                            Text("Day Streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 4) {
                            Text("\(heatmapData.count)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("Days Tracked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    // 6-month heatmap
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity")
                            .font(.headline)
                        HeatmapView(data: heatmapData, months: 6)
                            .frame(height: 70)
                    }
                    .cardStyle()

                    // Day-of-week distribution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Best Days")
                            .font(.headline)
                        DayOfWeekDistribution(data: heatmapData)
                            .frame(height: 60)
                    }
                    .cardStyle()

                    // Recent history
                    VStack(alignment: .leading, spacing: 10) {
                        Text("History")
                            .font(.headline)

                        ForEach(logs.prefix(30), id: \.date) { log in
                            HStack {
                                Image(systemName: log.done ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(log.done ? AppColors.statusGreen : AppColors.statusRed)
                                    .font(.body)
                                Text(log.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(.subheadline)
                                Spacer()
                                Text(log.done ? "Done" : "Missed")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(log.done ? AppColors.statusGreen : AppColors.statusRed)
                            }
                            if log.date != logs.prefix(30).last?.date {
                                Divider()
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
            .navigationTitle(name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
    }
}
