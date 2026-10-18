import SwiftUI

// MARK: - Notebook palette
//
// Ink on paper. One signal color for results outside a range, one amber for
// results near a limit or just outside it. Everything else is ink at
// different strengths. Values meet WCAG AA for text on paper in both modes.

enum Notebook {
    static let paper = Color(light: 0xF4F2EC, dark: 0x141413)
    /// Sheets and the few raised surfaces that still need grouping.
    static let paperRaised = Color(light: 0xF8F6F1, dark: 0x1B1B19)
    static let ink = Color(light: 0x1A1A18, dark: 0xEDEBE4)
    static let inkSecondary = Color(light: 0x6E6C64, dark: 0x9C9A91)
    /// Inactive tabs, placeholders and other non-essential text (3:1 or better).
    static let inkTertiary = Color(light: 0x7E7C74, dark: 0x85837A)
    static let rule = Color(light: 0x1A1A18, dark: 0xEDEBE4, opacity: 0.14)
    static let track = Color(light: 0x1A1A18, dark: 0xEDEBE4, opacity: 0.10)
    static let band = Color(light: 0x1A1A18, dark: 0xEDEBE4, opacity: 0.22)
    static let emptyBox = Color(light: 0x1A1A18, dark: 0xEDEBE4, opacity: 0.32)
    static let signal = Color(light: 0xC2410C, dark: 0xFB8A4C)
    static let near = Color(light: 0x8F5B10, dark: 0xE5B45A)

    // MARK: Type

    /// Numbers and data labels use SF Mono; names and prose stay in SF Pro.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

extension Color {
    /// An appearance-adaptive color from two hex values.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
        #else
        self.init(red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255, blue: Double(light & 0xFF) / 255, opacity: opacity)
        #endif
    }
}

// MARK: - Kicker

/// Small uppercase mono label above or below a title: "SUN 18 OCT 2026".
struct KickerModifier: ViewModifier {
    var color: Color = Notebook.inkSecondary

    func body(content: Content) -> some View {
        content
            .font(Notebook.mono(.caption))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func kicker(_ color: Color = Notebook.inkSecondary) -> some View {
        modifier(KickerModifier(color: color))
    }

    /// A full-width hairline under the content, the notebook's divider.
    func ruled(_ edge: VerticalEdge = .bottom) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) {
            Rectangle().fill(Notebook.rule).frame(height: 1)
        }
    }

    /// Paper background behind a whole screen, extending under the bars.
    func notebookBackground() -> some View {
        background(Notebook.paper.ignoresSafeArea())
    }
}

// MARK: - Section Header

/// "HEART ............ 1 FLAGGED" with a hairline underneath.
struct NotebookSectionHeader: View {
    let title: String
    var trailing: String?
    var trailingColor: Color = Notebook.inkSecondary

    var body: some View {
        // Stacks the count under the title when both don't fit on one line
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).kicker()
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).kicker(trailingColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).kicker()
                if let trailing {
                    Text(trailing).kicker(trailingColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 26)
        .padding(.bottom, 8)
        .ruled()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Underline Tabs

/// Mono uppercase tabs with one sliding underline (250 ms, strong ease-out).
/// Content changes directly; only the underline moves.
struct UnderlineTabs<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button {
                        if reduceMotion {
                            selection = option
                        } else {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)) { selection = option }
                        }
                    } label: {
                        Text(label(option))
                            .font(Notebook.mono(.footnote))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(isSelected ? Notebook.ink : Notebook.inkTertiary)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle()
                                        .fill(Notebook.ink)
                                        .frame(height: 2)
                                        .matchedGeometryEffect(id: "underline", in: underline)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .ruled()
    }
}

// MARK: - Status Word

/// A mono status word such as "in range" or "↑ above range". Text, not color,
/// carries the meaning; color only adds emphasis.
struct StatusWord: View {
    let text: String
    var color: Color = Notebook.inkSecondary

    var body: some View {
        Text(text)
            .font(Notebook.mono(.caption))
            .foregroundStyle(color)
    }
}

// MARK: - Note Line

/// "NOTE  Blood pressure is above your usual range today.   Dismiss"
struct NoteLine: View {
    let text: String
    var tag: String = "Note"
    /// Signal for warnings; pass `Notebook.inkSecondary` for neutral notes.
    var tagColor: Color = Notebook.signal
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(tag).kicker(tagColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(Notebook.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .font(Notebook.mono(.caption))
                    .underline()
                    .foregroundStyle(Notebook.inkSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Dismiss note")
            }
        }
        .padding(.vertical, 8)
        .ruled()
    }
}

// MARK: - Mini Range Bar

/// The inline bar on a list row: the reference band and a tick at the value.
struct MiniRangeBar: View {
    let value: Double
    let low: Double?
    let high: Double?
    var color: Color = Notebook.ink

    var body: some View {
        GeometryReader { geo in
            let scale = RangeScale(value: value, low: low, high: high)
            let w = geo.size.width
            let start = scale.x(low ?? scale.lower) * w
            let end = scale.x(high ?? scale.upper) * w
            ZStack(alignment: .leading) {
                Rectangle().fill(Notebook.track).frame(height: 4)
                Rectangle().fill(Notebook.band).frame(width: max(end - start, 2), height: 4).offset(x: start)
                Rectangle().fill(color).frame(width: 3, height: 14)
                    .offset(x: min(max(scale.x(value) * w - 1.5, 0), w - 3))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// Shared scale for range bars: the range plus 30% padding, widened to include
/// the value. With no lower limit the scale starts at zero for positive values.
struct RangeScale {
    let lower: Double
    let upper: Double

    init(value: Double, low: Double?, high: Double?) {
        let anchorLow = low ?? min(0, value)
        let anchorHigh = high ?? max((low ?? 0) * 2, value)
        let span = max(anchorHigh - anchorLow, abs(anchorHigh) * 0.1, 0.0001)
        var lower = low == nil ? anchorLow : anchorLow - span * 0.3
        var upper = anchorHigh + span * 0.3
        lower = min(lower, value - span * 0.05)
        upper = max(upper, value + span * 0.05)
        self.lower = lower
        self.upper = upper
    }

    func x(_ v: Double) -> CGFloat {
        CGFloat(min(max((v - lower) / (upper - lower), 0), 1))
    }
}

// MARK: - Bar Sparkline

/// Small bar chart for list rows; the latest bar is solid, earlier bars faint.
struct BarSparkline: View {
    let values: [Double]
    var highlight: Color = Notebook.ink
    /// Fixed bottom of the scale (for example 40 for 0–100 scores). Without it
    /// the scale starts just below the lowest value.
    var floor: Double?

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maxV = values.max(), let minV = values.min() else { return }
            let lo = floor ?? (minV - (maxV - minV) * 0.15 - 0.0001)
            let span = max(maxV - lo, 0.0001)
            let gap: CGFloat = values.count > 20 ? 1 : 2
            let barWidth = (size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
            for (i, v) in values.enumerated() {
                let h = max(2, CGFloat((v - lo) / span) * size.height)
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: size.height - h, width: barWidth, height: h)
                let isLast = i == values.count - 1
                context.fill(Path(rect), with: .color(isLast ? highlight : Notebook.ink.opacity(0.28)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Big Number

/// "15/16 in range", "69/100": a large mono number with a quiet suffix.
struct BigNumber: View {
    let value: String
    var suffix: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(Notebook.mono(.largeTitle, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Notebook.ink)
            if let suffix {
                Text(suffix)
                    .font(Notebook.mono(.subheadline))
                    .foregroundStyle(Notebook.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Blocks and Buttons

extension View {
    /// A detail-page section: vertical breathing room and a hairline below.
    func notebookBlock() -> some View {
        padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ruled()
    }
}

/// Filled ink button with paper-colored text; works in both appearances.
struct NotebookPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Notebook.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Notebook.ink, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Hairline-outlined ink button for secondary actions.
struct NotebookSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Notebook.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Notebook.ink.opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Checkbox

/// The notebook's tick box: filled ink with a check when on, an empty
/// outlined box when off, a slash when explicitly crossed out. Matches the
/// Habits grid. Decorative; the row it sits in carries the label and state.
struct NotebookCheckbox: View {
    let isOn: Bool
    var isCrossed = false

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 22
    private var size: CGFloat { min(scaledSize, 30) }

    var body: some View {
        Rectangle()
            .fill(isOn ? Notebook.ink : Color.clear)
            .overlay(Rectangle().stroke(isOn ? Notebook.ink : Notebook.emptyBox, lineWidth: 1.5))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .heavy))
                        .foregroundStyle(Notebook.paper)
                } else if isCrossed {
                    Path { p in
                        p.move(to: CGPoint(x: size * 0.22, y: size * 0.78))
                        p.addLine(to: CGPoint(x: size * 0.78, y: size * 0.22))
                    }
                    .stroke(Notebook.inkSecondary, lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Notebook Form

/// A grouped form in the Notebook look: paper rows on a raised-paper sheet,
/// hairline separators, ink tint. Use in place of `Form` for every sheet so
/// no screen falls back to the default white iOS form.
struct NotebookForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            // Group applies the row styling to every section inside
            Group { content }
                .listRowBackground(Notebook.paper)
                .listRowSeparatorTint(Notebook.rule)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Notebook.paperRaised.ignoresSafeArea())
        .foregroundStyle(Notebook.ink)
        .tint(Notebook.ink)
    }
}

/// A form section title in the Notebook kicker style.
struct NotebookFormHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).kicker()
    }
}

/// A form text field with its label always visible above it, so filled-in
/// fields stay identifiable (a placeholder disappears once there is text).
struct NotebookField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var axis: Axis = .horizontal

    init(_ label: String, text: Binding<String>, prompt: String = "", axis: Axis = .horizontal) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).kicker()
            TextField(label, text: $text, prompt: Text(prompt.isEmpty ? label : prompt).foregroundStyle(Notebook.inkTertiary), axis: axis)
                .font(.body)
                .foregroundStyle(Notebook.ink)
        }
        .padding(.vertical, 2)
    }
}
