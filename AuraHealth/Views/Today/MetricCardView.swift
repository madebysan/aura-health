import SwiftUI

/// One vitals row in the notebook table: name, status and change on the left,
/// the mono value in the middle, a bar sparkline on the right.
struct MetricCardView: View {
    let metricType: MetricType
    let latest: Measurement?
    let previous: Measurement?
    let recentValues: [Double]
    let onAdd: () -> Void

    /// Readings older than this get the muted "Last logged" state.
    private static let staleAfterDays = 7

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStale: Bool {
        guard let latest,
              let cutoff = Calendar.current.date(byAdding: .day, value: -Self.staleAfterDays, to: Date())
        else { return false }
        return latest.timestamp < cutoff
    }

    private var position: RangePosition? {
        latest.map { metricType.rangePosition(of: $0.value) }
    }

    var body: some View {
        Button(action: onAdd) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        nameBlock
                        valueBlock(alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        nameBlock
                            .frame(maxWidth: .infinity, alignment: .leading)
                        valueBlock(alignment: .trailing)
                        trendBlock
                            .frame(width: 64, height: 28)
                    }
                }
            }
            .padding(.vertical, 14)
            .ruled(.top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(latest == nil ? "Adds a measurement" : "Opens details")
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metricType.displayName)
                .font(.callout.weight(.medium))
                .foregroundStyle(Notebook.ink)
            if let latest {
                if isStale {
                    StatusWord(text: "last logged \(latest.timestamp.formatted(.dateTime.month(.abbreviated).day()))")
                } else {
                    if let position { statusIndicator(for: position) }
                    if let delta = deltaText {
                        StatusWord(text: delta)
                    }
                }
            } else {
                StatusWord(text: "tap to add")
            }
        }
    }

    private func valueBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(latest?.displayValue ?? "--")
                .font(Notebook.mono(.title3, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(latest == nil || isStale ? Notebook.inkTertiary : Notebook.ink)
                .contentTransition(.numericText())
            Text(metricType.unit)
                .font(Notebook.mono(.caption2))
                .foregroundStyle(Notebook.inkSecondary)
        }
    }

    @ViewBuilder
    private var trendBlock: some View {
        if !isStale, recentValues.count >= 2 {
            BarSparkline(values: recentValues, highlight: position == .within ? Notebook.ink : Notebook.signal)
        } else {
            Color.clear
        }
    }

    // MARK: - Status Indicator

    private func statusIndicator(for position: RangePosition) -> some View {
        let word = switch position {
        case .within: "in range"
        case .above: "↑ above typical"
        case .below: "↓ below typical"
        case .unknown: "no range"
        }
        return StatusWord(text: word, color: position.wordColor)
    }

    // MARK: - Delta

    /// "+0.4 kg since last", or nil when there is no previous reading.
    private var deltaText: String? {
        guard let latest, let previous else { return nil }
        let diff = latest.value - previous.value
        if abs(diff) < 0.01 { return "no change since last" }
        let sign = diff > 0 ? "+" : "−"
        let magnitude = abs(diff) == abs(diff).rounded() ? "\(Int(abs(diff)))" : String(format: "%.1f", abs(diff))
        let unit = metricType.unit == "%" ? "%" : " \(metricType.unit)"
        return "\(sign)\(magnitude)\(unit) since last"
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
    VStack(spacing: 0) {
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
