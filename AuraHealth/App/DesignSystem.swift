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
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            #else
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
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
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                .overlay(isActive ? Capsule().stroke(Color.accentColor.opacity(0.2), lineWidth: 1) : nil)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

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
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
