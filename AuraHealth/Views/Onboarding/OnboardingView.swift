import SwiftUI
import SwiftData

/// Three screens: what Aura is (with the privacy promise), then two numbered
/// steps: Apple Health with units, and the assistant. Diet now lives in the
/// Health Profile, and cloud AI keys are an advanced option in Settings.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius

    @State private var phase: OnboardingPhase = .welcome
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scaledIconSize: CGFloat = 72

    enum OnboardingPhase {
        case welcome
        case data
        case assistant
    }

    private static let stepCount = 2

    var body: some View {
        Group {
            switch phase {
            case .welcome: welcomeView
            case .data: dataView
            case .assistant: assistantView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .notebookBackground()
        .tint(Notebook.ink)
    }

    // MARK: - Page Layout

    /// One onboarding screen on paper: content starts at the top and scrolls
    /// when text is large or the screen is small; actions sit at the bottom.
    private func page<Content: View, Actions: View>(
        step: Int? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        let content = content()
        let actions = actions()
        return GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let step {
                        Text("Step \(step) of \(Self.stepCount)")
                            .kicker()
                            .padding(.bottom, 20)
                    }
                    VStack(alignment: .leading, spacing: 28) {
                        content
                    }
                    Spacer(minLength: 32)
                    VStack(spacing: 4) {
                        actions
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Notebook.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(Notebook.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An icon, a short claim and one sentence under it.
    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(icon)
                .font(.title3)
                .foregroundStyle(Notebook.ink)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Notebook.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Notebook.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        page {
            let iconSize = min(scaledIconSize, 120)
            Image("AuraIcon")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
                        .stroke(Notebook.rule, lineWidth: 1)
                )
                .accessibilityHidden(true)

            pageTitle("Aura", subtitle: "Your vitals, labs, medications and habits, read clearly.")

            VStack(spacing: 0) {
                point("ph.heartbeat", "What changed, in one sentence",
                      "Apple Health and your own entries, with anything outside your typical range on top.")
                point("ph.test-tube", "Every lab report, kept",
                      "Each marker with its history and reference range.")
                point("ph.device-mobile", "Private by default",
                      "No account. Your data stays on this iPhone, and the assistant runs on it too.")
            }
            .ruled(.top)
        } actions: {
            Button("Set Up Aura") {
                phase = .data
            }
            .buttonStyle(NotebookPrimaryButtonStyle())
            .padding(.bottom, 8)

            Button("Explore with Sample Data") {
                SampleDataService.loadSampleData(into: modelContext)
                hasCompletedOnboarding = true
            }
            .buttonStyle(NotebookSecondaryButtonStyle())
        }
    }

    // MARK: - Step 1: Apple Health and units

    private var dataView: some View {
        page(step: 1) {
            pageTitle("Your data", subtitle: "Bring in what Apple Health already knows, and pick your units.")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Health")
                            .font(.headline)
                            .foregroundStyle(Notebook.ink)
                        Text("Heart rate, sleep, steps, weight and more.")
                            .font(.subheadline)
                            .foregroundStyle(Notebook.inkSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if healthKitService.hasRequestedAccess {
                        StatusWord(text: "requested", color: Notebook.ink)
                    } else if healthKitService.isAvailable {
                        Button("Connect") {
                            Task { await healthKitService.requestAuthorization() }
                        }
                        .font(Notebook.mono(.subheadline, weight: .medium))
                        .foregroundStyle(Notebook.ink)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    } else {
                        StatusWord(text: "not available")
                    }
                }
                Text("Read-only. Aura never writes to Apple Health, and you can change access any time in the Health app.")
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .ruled(.top)

            VStack(spacing: 0) {
                unitRow("Weight") {
                    PillSegmentedPicker(options: WeightUnit.allCases, selection: $weightUnit, label: { $0.symbol })
                        .fixedSize()
                }
                unitRow("Temperature") {
                    PillSegmentedPicker(options: TemperatureUnit.allCases, selection: $temperatureUnit, label: { $0.symbol })
                        .fixedSize()
                }
            }
            .ruled(.top)
        } actions: {
            Button("Continue") {
                phase = .assistant
            }
            .buttonStyle(NotebookPrimaryButtonStyle())
        }
    }

    private func unitRow<Picker: View>(_ title: String, @ViewBuilder picker: () -> Picker) -> some View {
        // At accessibility text sizes the picker moves under the label
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(title)
                .font(.headline)
                .foregroundStyle(Notebook.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            picker()
        }
        .padding(.vertical, 12)
        .ruled()
    }

    // MARK: - Step 2: Assistant

    private var assistantView: some View {
        page(step: 2) {
            pageTitle("Your assistant", subtitle: "Ask about your own records, or log a reading by typing it.")

            VStack(spacing: 0) {
                point("ph.chats", "Ask in plain words",
                      "\u{201C}How did I sleep this week?\u{201D} or \u{201C}What changed in my labs?\u{201D}")
                point("ph.note-pencil", "Log by typing",
                      "\u{201C}Log my weight at 81 kg.\u{201D} Aura asks before it saves anything.")
                if let reason = OnDeviceAssistant.unavailableReason {
                    point("ph.device-mobile", "Not available yet", reason)
                } else {
                    point("ph.device-mobile", "Runs on this iPhone",
                          "Apple's on-device model. Nothing is sent anywhere.")
                }
            }
            .ruled(.top)

            Text("Aura is not a medical device. The assistant explains your data; it doesn't diagnose. To use Anthropic or OpenRouter with your own key instead, go to Settings.")
                .font(.footnote)
                .foregroundStyle(Notebook.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Start Using Aura") {
                hasCompletedOnboarding = true
            }
            .buttonStyle(NotebookPrimaryButtonStyle())
        }
    }
}
