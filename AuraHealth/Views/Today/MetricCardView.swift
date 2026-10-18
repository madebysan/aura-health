import SwiftUI

/// One vitals row in the notebook table: the name (plus a status word only when the
/// reading is outside its typical range), the mono value, and a bar sparkline.
struct MetricCardView: View {
    let metricType: MetricType
    let latest: Measurement?
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
                } else if let position, position != .within {
                    // In range is the normal state, so only flags get a word.
                    statusIndicator(for: position)
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
            BarSparkline(values: recentValues, highlight: position?.color ?? Notebook.ink)
        } else if !isStale, recentValues.count == 1 {
            // One reading this week: say so instead of leaving the column blank
            Text("1 reading")
                .font(Notebook.mono(.caption2))
                .foregroundStyle(Notebook.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
}

#Preview {
    VStack(spacing: 0) {
        MetricCardView(
            metricType: .heartRate,
            latest: Measurement(metricType: .heartRate, value: 72),
            recentValues: [68, 72, 70, 74, 72, 69, 72],
            onAdd: {}
        )

        MetricCardView(
            metricType: .bloodPressure,
            latest: Measurement(metricType: .bloodPressure, value: 118, value2: 76),
            recentValues: [120, 118, 122, 115, 118],
            onAdd: {}
        )

        MetricCardView(
            metricType: .weight,
            latest: nil,
            recentValues: [],
            onAdd: {}
        )
    }
    .padding()
}
