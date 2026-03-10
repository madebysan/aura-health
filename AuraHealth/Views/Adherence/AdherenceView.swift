import SwiftUI

// MARK: - Heatmap View (reusable)

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

    /// Organizes days into weeks (columns) with 7 rows each (Mon–Sun).
    private var weeks: [[Date?]] {
        guard let first = days.first else { return [] }
        // Weekday: 1=Sun, 2=Mon ... 7=Sat. We want Mon=0, so shift.
        let firstWeekday = (calendar.component(.weekday, from: first) + 5) % 7
        var grid: [[Date?]] = []
        var week: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in days {
            week.append(day)
            if week.count == 7 {
                grid.append(week)
                week = []
            }
        }
        if !week.isEmpty {
            while week.count < 7 { week.append(nil) }
            grid.append(week)
        }
        return grid
    }

    var body: some View {
        GeometryReader { geo in
            let weekCount = max(weeks.count, 1)
            let totalSpacing = CGFloat(weekCount - 1) * 2
            let cellSize = max(4, (geo.size.width - totalSpacing) / CGFloat(weekCount))

            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { row in
                            if let day = week[row] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForDay(day))
                                    .frame(width: cellSize, height: cellSize)
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(max(weeks.count, 1)) / 7.0, contentMode: .fit)
    }

    private func colorForDay(_ day: Date) -> Color {
        guard let done = data[day] else { return Color.primary.opacity(0.04) }
        return done ? AppColors.statusGreen.opacity(0.7) : AppColors.statusRed.opacity(0.35)
    }
}
