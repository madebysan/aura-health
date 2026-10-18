import SwiftUI

// MARK: - Named Animation Curves

/// Centralized animation presets — never use bare `withAnimation`.
enum AppAnimation {
    /// Editor opens, detail reveals (0.4s, bounce)
    static let expand = Animation.spring(duration: 0.4, bounce: 0.18)
    /// Editor closes, faster rebound (0.25s, bounce)
    static let collapse = Animation.spring(duration: 0.25, bounce: 0.06)
    /// Item fades from list after completion (0.5s)
    static let complete = Animation.easeOut(duration: 0.5)
    /// New item appears in list (0.35s, bounce)
    static let appear = Animation.spring(duration: 0.35, bounce: 0.12)
    /// Tab/view crossfade — should feel invisible (0.2s)
    static let viewSwitch = Animation.easeInOut(duration: 0.2)
    /// Fast button press, no bounce (0.12s)
    static let quickToggle = Animation.easeInOut(duration: 0.12)
    /// Drag drop with physical impact (0.35s, bounce)
    static let dragSettle = Animation.spring(duration: 0.35, bounce: 0.22)
    /// Staggered row delay (per-row offset)
    static func stagger(index: Int, base: Double = 0.03) -> Animation {
        .spring(duration: 0.35, bounce: 0.12).delay(Double(min(index, 15)) * base)
    }
    /// Score ring fill animation
    static let scoreRing = Animation.easeOut(duration: 1.0)
    /// Card hover lift
    static let hover = Animation.easeInOut(duration: 0.15)
}

// MARK: - Color Tokens

enum AppColors {
    // Accent
    static let accent = Color.accentColor

    // Surfaces
    #if os(macOS)
    static let cardBackground = Color(.controlBackgroundColor)
    #else
    static let cardBackground = Color(.secondarySystemBackground)
    #endif
    static let cardBorder = Color.primary.opacity(0.06)
    static let cardBorderHover = Color.primary.opacity(0.12)

    // Interactive states
    static let selectionFill = Color.primary.opacity(0.08)
    static let hoverBackground = Color.primary.opacity(0.04)

    // Biomarker status
    static func biomarkerColor(_ status: BiomarkerStatus) -> Color {
        switch status {
        case .normal: Notebook.inRange
        case .borderline: Notebook.near
        case .abnormal: Notebook.outOfRange
        case .unknown: Notebook.inkTertiary
        }
    }

    /// Color for one result: values just outside the range use ochre, so brick
    /// is kept for results clearly outside it.
    static func biomarkerColor(_ biomarker: Biomarker) -> Color {
        if biomarker.status == .abnormal && biomarker.isMarginallyOutOfRange {
            return Notebook.near
        }
        return biomarkerColor(biomarker.status)
    }

    /// Color for a status word: sage, ochre or brick.
    static func biomarkerWordColor(_ biomarker: Biomarker) -> Color {
        biomarkerColor(biomarker)
    }
}

// MARK: - Number Formatting

enum AppFormat {
    /// Trims trailing zeros: 100 → "100", 5.4 → "5.4", 0.125 → "0.13".
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "40–200 mg/dL", "under 100 mg/dL" or "over 40 mg/dL".
    static func range(low: Double?, high: Double?, unit: String) -> String {
        let suffix = unit.isEmpty ? "" : " \(unit)"
        switch (low, high) {
        case let (low?, high?): return "\(number(low))–\(number(high))\(suffix)"
        case let (nil, high?): return "under \(number(high))\(suffix)"
        case let (low?, nil): return "over \(number(low))\(suffix)"
        case (nil, nil): return "not set"
        }
    }
}

// MARK: - Range Position

extension RangePosition {
    /// Sage when in range, brick when outside.
    var color: Color {
        switch self {
        case .within: Notebook.inRange
        case .below, .above: Notebook.outOfRange
        case .unknown: Notebook.inkTertiary
        }
    }

    /// Color for the status word next to a value.
    var wordColor: Color { color }

    var label: String {
        switch self {
        case .below: "Below range"
        case .within: "In range"
        case .above: "Above range"
        case .unknown: "No range"
        }
    }
}

extension MetricType {
    /// Position of a value against this metric's typical range.
    func rangePosition(of value: Double) -> RangePosition {
        let range = defaultRange
        if value < range.low { return .below }
        if value > range.high { return .above }
        return .within
    }
}

// MARK: - Chart Summaries

/// Spoken summaries for charts, so VoiceOver users get the takeaway
/// instead of a list of unlabeled points.
enum ChartSummary {
    /// "12 readings from Sep 20 to Oct 17. Latest 82.3 kg. Low 81.5, high 82.4. Trending up."
    static func trend(points: [(date: Date, value: Double)], unit: String) -> String {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return "No readings" }
        let values = sorted.map(\.value)
        let unitText = unit.isEmpty ? "" : " \(unit)"
        let dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()
        var parts = [
            "\(sorted.count) \(sorted.count == 1 ? "reading" : "readings") from \(first.date.formatted(dateStyle)) to \(last.date.formatted(dateStyle))",
            "Latest \(AppFormat.number(last.value))\(unitText)"
        ]
        if let low = values.min(), let high = values.max(), low != high {
            parts.append("Low \(AppFormat.number(low)), high \(AppFormat.number(high))")
        }
        if sorted.count > 1 {
            parts.append(direction(from: first.value, to: last.value))
        }
        return parts.joined(separator: ". ") + "."
    }

    /// "Trending up", "Trending down" or "Steady", using a 2% threshold.
    static func direction(from start: Double, to end: Double) -> String {
        let scale = max(abs(start), 0.0001)
        let change = (end - start) / scale
        if change > 0.02 { return "Trending up" }
        if change < -0.02 { return "Trending down" }
        return "Steady"
    }
}

// MARK: - Range Status Icon

/// Shape-coded status so in-range and out-of-range never rely on color alone.
struct RangeStatusIcon: View {
    let position: RangePosition
    var color: Color = .secondary

    var body: some View {
        Image(symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel(position.label)
    }

    private var symbolName: String {
        switch position {
        case .below: "ph.arrow-circle-down"
        case .within: "ph.check-circle"
        case .above: "ph.arrow-circle-up"
        case .unknown: "ph.circle-dashed"
        }
    }
}

// MARK: - Reference Range Bar

/// Plots a value against its reference range. The shaded band is the range
/// and its limit labels sit at the band's own edges. Pass `nil` for a missing
/// limit, such as LDL's "under 100", so no meaningless zone is drawn there.
struct ReferenceRangeBar: View {
    let value: Double
    let low: Double?
    let high: Double?
    let valueColor: Color
    var unit: String = ""
    var title: String = "Reference range"

    @ScaledMetric(relativeTo: .caption2) private var tickHeight: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 16

    var body: some View {
        let scale = RangeScale(value: value, low: low, high: high)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let bandStart = scale.x(low ?? scale.lower) * width
                let bandEnd = scale.x(high ?? scale.upper) * width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Notebook.track).frame(height: 4)
                    Rectangle().fill(Notebook.band)
                        .frame(width: max(bandEnd - bandStart, 2), height: 4)
                        .offset(x: bandStart)
                    Rectangle().fill(valueColor)
                        .frame(width: 4, height: tickHeight)
                        .offset(x: min(max(scale.x(value) * width - 2, 0), width - 4))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: tickHeight)

            // Limit labels, placed under the band edges they describe
            GeometryReader { geo in
                let width = geo.size.width
                if let low {
                    limitLabel(low, x: scale.x(low) * width, width: width)
                }
                if let high {
                    limitLabel(high, x: scale.x(high) * width, width: width)
                }
            }
            .frame(height: labelHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func limitLabel(_ limit: Double, x: CGFloat, width: CGFloat) -> some View {
        Text(AppFormat.number(limit))
            .font(Notebook.mono(.caption2))
            .foregroundStyle(Notebook.inkSecondary)
            .fixedSize()
            .position(x: min(max(x, 14), width - 14), y: labelHeight / 2)
    }

    private var accessibilityValue: String {
        let position: String
        if let low, value < low {
            position = "below range"
        } else if let high, value > high {
            position = "above range"
        } else {
            position = "in range"
        }
        let unitText = unit.isEmpty ? "" : " \(unit)"
        return "\(AppFormat.number(value))\(unitText), \(position). Range \(AppFormat.range(low: low, high: high, unit: unit))"
    }
}

// MARK: - Card Style Modifier

/// Notebook surfaces are flat: raised paper and a hairline, no material or shadow.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Notebook.paperRaised, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Notebook.rule, lineWidth: 1))
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 14) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Staggered Appearance Modifier

struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(AppAnimation.stagger(index: index)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}

// MARK: - Hover Card Modifier (macOS)

struct HoverCard: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 1)
            .animation(AppAnimation.hover, value: isHovered)
            .onHover { isHovered = $0 }
            #endif
    }
}

extension View {
    func hoverCard() -> some View {
        modifier(HoverCard())
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionLabel: String = "See All"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())

            Spacer()

            if let action {
                Button(actionLabel, action: action)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Status Badge

/// A short labeled state, written as a mono word. `style` is kept for
/// compatibility; outlined badges get a hairline box.
struct StatusBadge: View {
    let label: String
    let color: Color
    var style: BadgeStyle = .filled

    enum BadgeStyle {
        case filled, outlined
    }

    var body: some View {
        Text(label)
            .font(Notebook.mono(.caption2, weight: .medium))
            .textCase(.lowercase)
            .padding(.horizontal, style == .outlined ? 6 : 0)
            .padding(.vertical, style == .outlined ? 2 : 0)
            .overlay(style == .outlined ? Rectangle().stroke(color.opacity(0.4), lineWidth: 1) : nil)
            .foregroundStyle(color)
    }
}

// MARK: - Pill Segmented Picker

/// Small mutually exclusive choices, drawn as notebook underline tabs.
struct PillSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        UnderlineTabs(options: options, selection: $selection, label: label)
    }
}

// MARK: - Haptics (iOS only)

#if os(iOS)
/// Lightweight haptic helpers so any view can trigger feedback without
/// importing UIKit directly.
enum AppHaptics {
    /// A single solid impact — used for habit completion.
    static func impact(flexibility: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: flexibility).impactOccurred()
    }

    /// A notification haptic — success, warning, or error.
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
#endif

// MARK: - Inline Error Banner

/// A recoverable problem written as a notebook line: a mono tag and the
/// message, with a hairline above and below. The tag word carries the meaning.
struct InlineErrorBanner: View {
    let message: String
    var style: BannerStyle = .error

    enum BannerStyle {
        case error, warning

        var tag: String {
            switch self {
            case .error: "Error"
            case .warning: "Note"
            }
        }

        var color: Color {
            switch self {
            case .error: Notebook.signal
            case .warning: Notebook.near
            }
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(style.tag).kicker(style.color)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Notebook.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?
    var chatHint: String?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Notebook.inkTertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Notebook.ink)

            Text(message)
                .font(.body)
                .foregroundStyle(Notebook.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }

            if let chatHint {
                Label(chatHint, image: "ph.chat-circle")
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .onAppear {
            withAnimation(AppAnimation.appear.delay(0.05)) {
                appeared = true
            }
        }
    }
}
