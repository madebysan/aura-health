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

    // Status
    static let statusGreen = Color.green
    static let statusOrange = Color.orange
    static let statusRed = Color.red

    // Score bands
    static func scoreColor(for score: Double) -> Color {
        switch score {
        case 80...100: .green
        case 70..<80: Color(red: 0.45, green: 0.75, blue: 0.15) // lime green
        case 60..<70: .yellow
        case 40..<60: .orange
        default: .red
        }
    }

    // Biomarker status
    static func biomarkerColor(_ status: BiomarkerStatus) -> Color {
        switch status {
        case .normal: .green
        case .borderline: .orange
        case .abnormal: .red
        case .unknown: .gray
        }
    }
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            #if os(macOS)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            #else
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            #endif
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

struct StatusBadge: View {
    let label: String
    let color: Color
    var style: BadgeStyle = .filled

    enum BadgeStyle {
        case filled, outlined
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                style == .filled
                    ? AnyShapeStyle(color.opacity(0.12))
                    : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .overlay(
                style == .outlined
                    ? Capsule().stroke(color.opacity(0.3), lineWidth: 1)
                    : nil
            )
            .foregroundStyle(color)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                .overlay(isActive ? Capsule().stroke(Color.accentColor.opacity(0.2), lineWidth: 1) : nil)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

// MARK: - Pill Segmented Picker

struct PillSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let isSelected = selection == option
                Button {
                    withAnimation(AppAnimation.viewSwitch) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pillNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                // Divider between non-selected items
                let nextIsSelected = index + 1 < options.count && selection == options[index + 1]
                if index < options.count - 1 && !isSelected && !nextIsSelected {
                    Divider()
                        .frame(height: 14)
                        .opacity(0.3)
                }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
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

struct InlineErrorBanner: View {
    let message: String
    var style: BannerStyle = .error

    enum BannerStyle {
        case error, warning

        var icon: String {
            switch self {
            case .error: "exclamationmark.triangle.fill"
            case .warning: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: AppColors.statusRed
            case .warning: AppColors.statusOrange
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.color)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(12)
        .background(style.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(style.color.opacity(0.15), lineWidth: 1)
        )
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
            Image(systemName: icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(title)
                .font(.title3.weight(.medium))

            Text(message)
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }

            if let chatHint {
                Label(chatHint, systemImage: "bubble.left.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
