import SwiftUI

struct HealthScoreRingView: View {
    let score: Double
    let label: String
    var size: CGFloat = 120

    @State private var animatedProgress: Double = 0

    private var normalizedScore: Double {
        min(max(score / 100, 0), 1)
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: score)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(scoreColor.opacity(0.1), lineWidth: ringWidth)

            // Track (subtle)
            Circle()
                .stroke(Color.primary.opacity(0.04), lineWidth: ringWidth)

            // Score arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [scoreColor.opacity(0.6), scoreColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glow dot at end of arc
            Circle()
                .fill(scoreColor.shadow(.drop(color: scoreColor.opacity(0.5), radius: 4)))
                .frame(width: ringWidth + 2, height: ringWidth + 2)
                .offset(y: -size / 2 + ringWidth / 2)
                .rotationEffect(.degrees(animatedProgress * 360 - 90))
                .opacity(animatedProgress > 0 ? 1 : 0)

            // Center text
            VStack(spacing: 1) {
                Text("\(Int(score))")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(label)
                    .font(.system(size: size * 0.09, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(AppAnimation.scoreRing) {
                animatedProgress = normalizedScore
            }
        }
        .onChange(of: score) {
            withAnimation(AppAnimation.scoreRing) {
                animatedProgress = normalizedScore
            }
        }
    }

    private var ringWidth: CGFloat {
        size * 0.09
    }
}

#Preview {
    HStack(spacing: 24) {
        HealthScoreRingView(score: 85, label: "Daily Health")
        HealthScoreRingView(score: 62, label: "Composite", size: 80)
        HealthScoreRingView(score: 35, label: "Low", size: 80)
    }
    .padding()
}
