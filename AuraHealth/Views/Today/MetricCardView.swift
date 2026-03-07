import SwiftUI

struct MetricCardView: View {
    let metricType: MetricType
    let latest: Measurement?
    let previous: Measurement?
    let recentValues: [Double]
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: metricType.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(metricType.iconColor)
                        .frame(width: 20, height: 20)
                        .background(metricType.iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                    Text(metricType.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Status dot
                    if let latest {
                        statusIndicator(for: latest)
                    }
                }

                // Value
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let latest {
                        Text(latest.displayValue)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())

                        Text(metricType.unit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("--")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.quaternary)
                    }
                }

                // Delta
                if let delta = deltaInfo {
                    HStack(spacing: 3) {
                        Image(systemName: delta.direction == .up ? "arrow.up.right" : delta.direction == .down ? "arrow.down.right" : "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(delta.text)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(delta.color)
                } else if latest != nil {
                    Text(" ")
                        .font(.caption2)
                }

                // Sparkline
                if recentValues.count >= 2 {
                    SparklineView(values: recentValues, color: metricType.iconColor)
                        .frame(height: 30)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 30)
                }

                // Timestamp
                if let latest {
                    Text(latest.timestamp, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                } else {
                    Text("Tap to add")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(padding: 14, cornerRadius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverCard()
    }

    // MARK: - Status Indicator

    private func statusIndicator(for measurement: Measurement) -> some View {
        let range = metricType.defaultRange
        let inRange = measurement.value >= range.low && measurement.value <= range.high
        return Circle()
            .fill(inRange ? AppColors.statusGreen : AppColors.statusOrange)
            .frame(width: 8, height: 8)
            .shadow(color: (inRange ? AppColors.statusGreen : AppColors.statusOrange).opacity(0.4), radius: 3)
    }

    // MARK: - Delta

    private enum Direction { case up, down, flat }

    private struct DeltaInfo {
        let text: String
        let color: Color
        let direction: Direction
    }

    private var deltaInfo: DeltaInfo? {
        guard let latest, let previous else { return nil }
        let diff = latest.value - previous.value
        if abs(diff) < 0.01 { return nil }

        let sign = diff > 0 ? "+" : ""
        let text: String
        if diff == diff.rounded() {
            text = "\(sign)\(Int(diff)) \(metricType.unit)"
        } else {
            text = "\(sign)\(String(format: "%.1f", diff)) \(metricType.unit)"
        }

        let direction: Direction = diff > 0 ? .up : .down
        let color: Color
        switch metricType {
        case .recovery, .sleepScore, .hrv, .spo2, .sleepDuration, .steps, .activeMinutes:
            // Higher is better
            color = diff > 0 ? AppColors.statusGreen : AppColors.statusOrange
        case .heartRate, .strain:
            // Lower is generally better at rest
            color = diff < 0 ? AppColors.statusGreen : AppColors.statusOrange
        default:
            color = .secondary
        }

        return DeltaInfo(text: text, color: color, direction: direction)
    }
}

// MARK: - MetricType icon colors

extension MetricType {
    var iconColor: Color {
        switch self {
        case .weight: .indigo
        case .bloodPressure: .red
        case .heartRate: .pink
        case .sleepScore: .purple
        case .sleepDuration: .purple.opacity(0.8)
        case .steps: .teal
        case .activeMinutes: .orange
        case .hrv: .cyan
        case .recovery: .green
        case .strain: .red.opacity(0.8)
        case .spo2: .blue
        case .skinTemp: .orange.opacity(0.8)
        case .calories: .orange
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
        MetricCardView(
            metricType: .heartRate,
            latest: Measurement(metricType: .heartRate, value: 72),
            previous: Measurement(
                timestamp: Calendar.current.date(byAdding: .hour, value: -6, to: Date())!,
                metricType: .heartRate, value: 68
            ),
            recentValues: [68, 72, 70, 74, 72, 69, 72],
            onAdd: {}
        )

        MetricCardView(
            metricType: .bloodPressure,
            latest: Measurement(metricType: .bloodPressure, value: 118, value2: 76),
            previous: nil,
            recentValues: [120, 118, 122, 115, 118],
            onAdd: {}
        )

        MetricCardView(
            metricType: .weight,
            latest: nil,
            previous: nil,
            recentValues: [],
            onAdd: {}
        )
    }
    .padding()
}
