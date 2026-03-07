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

    var body: some View {
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(9), spacing: 2), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForDay(day))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func colorForDay(_ day: Date) -> Color {
        guard let done = data[day] else { return Color.primary.opacity(0.04) }
        return done ? AppColors.statusGreen.opacity(0.7) : AppColors.statusRed.opacity(0.35)
    }
}
