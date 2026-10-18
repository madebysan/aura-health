import SwiftUI

struct MetricCardView: View {
    let metricType: MetricType
    let latest: Measurement?
    let previous: Measurement?
    let recentValues: [Double]
    let onAdd: () -> Void

    /// Readings older than this get the muted "Last logged" state.
    private static let staleAfterDays = 7

    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var sparklineHeight: CGFloat = 30

    private var isStale: Bool {
        guard let latest,
              let cutoff = Calendar.current.date(byAdding: .day, value: -Self.staleAfterDays, to: Date())
        else { return false }
        return latest.timestamp < cutoff
    }

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: metricType.iconName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(metricType.iconColor)
                        .frame(width: iconSize, height: iconSize)
                        .background(metricType.iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)

                    Text(metricType.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    // Status icon (shape-coded, not color alone)
                    if let latest, !isStale {
                        statusIndicator(for: latest)
                    }
                }

                // Value
                ViewThatFits(in: .horizontal) {
                    valueRow(axis: .horizontal)
                    valueRow(axis: .vertical)
                }

                if isStale {
                    // Old reading: say so instead of showing an empty chart
                    Text("No readings in the last \(Self.staleAfterDays) days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: sparklineHeight, alignment: .leading)
                } else {
                    // Delta (always reserve space so cards align)
                    if let delta = deltaInfo {
                        HStack(spacing: 3) {
                            Image(systemName: delta.direction == .up ? "arrow.up.right" : delta.direction == .down ? "arrow.down.right" : "arrow.right")
                                .font(.caption2.weight(.bold))
                                .accessibilityHidden(true)
                            Text(delta.text)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(delta.color)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Change since previous: \(delta.text)")
                    } else {
                        Text(" ")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }

                    // Sparkline (always reserve space)
                    if recentValues.count >= 2 {
                        SparklineView(values: recentValues, color: metricType.iconColor)
                            .frame(height: sparklineHeight)
                            .clipped()
                            .accessibilityHidden(true)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: sparklineHeight)
                            .accessibilityHidden(true)
                    }
                }

                // Footer (always at bottom, same position)
                if let latest {
                    if isStale {
                        Text("Last logged \(latest.timestamp.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(latest.timestamp, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Tap to add")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(padding: 14, cornerRadius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint(latest == nil ? "Adds a measurement" : "Opens details")
    }

    @ViewBuilder
    private func valueRow(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            if let latest {
                Text(latest.displayValue)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isStale ? HierarchicalShapeStyle.secondary : .primary)
                    .contentTransition(.numericText())

                Text(metricType.unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            } else {
                Text("--")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.quaternary)
                    .accessibilityLabel("No data")
            }
        }
    }

    // MARK: - Status Indicator

    private func statusIndicator(for measurement: Measurement) -> some View {
        let position = metricType.rangePosition(of: measurement.value)
        return RangeStatusIcon(position: position, color: position.color)
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
