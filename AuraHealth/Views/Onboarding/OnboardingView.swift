import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage("aiProvider") private var aiProvider: AIProvider = .anthropic
    @AppStorage("aiModel") private var aiModelID = AIProviderCatalog.defaultModelID(for: .anthropic)

    @State private var phase: OnboardingPhase = .welcome
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scaledIconSize: CGFloat = 88

    enum OnboardingPhase {
        case welcome
        case features
        case connect
        case preferences
        case diet
        case chat
    }

    var body: some View {
        Group {
            switch phase {
            case .welcome:
                welcomeView
            case .features:
                featuresView
            case .connect:
                connectView
            case .preferences:
                preferencesView
            case .diet:
                dietSetupView
            case .chat:
                chatSetupView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .notebookBackground()
        .tint(Notebook.ink)
    }

    // MARK: - Page Layout

    /// One onboarding step on paper: content sits in the middle when it fits
    /// and scrolls when text is large or the screen is small. Actions follow.
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
                        Text("Step \(step) of 4").kicker()
                    }
                    Spacer(minLength: 24)
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
                .padding(.vertical, 20)
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

    /// A quiet text-only action such as "Skip for Now".
    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Notebook.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Welcome (Mock Data Prompt)

    private var welcomeView: some View {
        page {
            let iconSize = min(scaledIconSize, 140)
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

            pageTitle("Welcome to Aura", subtitle: "Your personal health companion")
        } actions: {
            Text("Want to explore with sample data?")
                .font(.subheadline)
                .foregroundStyle(Notebook.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            Button("Load Sample Data") {
                SampleDataService.loadSampleData(into: modelContext)
                hasCompletedOnboarding = true
            }
            .buttonStyle(NotebookPrimaryButtonStyle())
            .padding(.bottom, 8)

            Button("Set Up Aura") {
                phase = .features
            }
            .buttonStyle(NotebookSecondaryButtonStyle())
        }
    }

    // MARK: - Feature Highlights

    @State private var featurePage = 0

    private let features: [(icon: String, title: String, description: String)] = [
        (
            "heart.text.square",
            "Track Your Vitals",
            "Monitor heart rate, HRV, sleep, recovery, and more — all in one place. See trends over time with clear charts."
        ),
        (
            "cross.vial",
            "Lab Results & Biomarkers",
            "Import your blood work and review biomarker changes across tests."
        ),
        (
            "bubble.left.and.bubble.right",
            "AI Health Chat",
            "Ask questions about your health data. Get personalized insights powered by Claude."
        ),
    ]

    private var featuresView: some View {
        VStack(spacing: 0) {
            TabView(selection: $featurePage) {
                ForEach(0..<features.count, id: \.self) { index in
                    GeometryReader { geo in
                        ScrollView {
                            featureCard(index: index)
                                .frame(maxWidth: 520, alignment: .leading)
                                .padding(.horizontal, 28)
                                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            VStack(spacing: 12) {
                // Page marks: the current page is a solid ink bar
                HStack(spacing: 6) {
                    ForEach(0..<features.count, id: \.self) { index in
                        Rectangle()
                            .fill(index == featurePage ? Notebook.ink : Notebook.band)
                            .frame(width: 20, height: 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                Button(featurePage < features.count - 1 ? "Next" : "Get Started") {
                    if featurePage < features.count - 1 {
                        withAnimation { featurePage += 1 }
                    } else {
                        phase = .connect
                    }
                }
                .buttonStyle(NotebookPrimaryButtonStyle())

                if featurePage < features.count - 1 {
                    textButton("Skip") { phase = .connect }
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private func featureCard(index: Int) -> some View {
        let feature = features[index]
        return VStack(alignment: .leading, spacing: 18) {
            Text(String(format: "%02d / %02d", index + 1, features.count))
                .kicker()
                .accessibilityLabel("Page \(index + 1) of \(features.count)")

            Image(systemName: feature.icon)
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(Notebook.ink)
                .accessibilityHidden(true)

            Text(feature.title)
                .font(.title.bold())
                .foregroundStyle(Notebook.ink)
                .accessibilityAddTraits(.isHeader)

            Text(feature.description)
                .font(.body)
                .foregroundStyle(Notebook.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Connect Integrations

    private var connectView: some View {
        page(step: 1) {
            pageTitle("Connect Your Data", subtitle: "Link a data source to get started")

            #if os(iOS)
            integrationButton(
                icon: "heart.text.square",
                title: "Connect Apple Health",
                subtitle: healthKitService.hasRequestedAccess ? "Access requested" : "Import activity, sleep, heart rate, and more",
                connected: healthKitService.hasRequestedAccess
            ) {
                Task { await healthKitService.requestAuthorization() }
            }
            #endif
        } actions: {
            Button("Continue") {
                phase = .preferences
            }
            .buttonStyle(NotebookPrimaryButtonStyle())

            textButton("Skip for Now") { phase = .preferences }
        }
    }

    // MARK: - Preferences (Units)

    private var preferencesView: some View {
        page(step: 2) {
            pageTitle("Your Preferences", subtitle: "Choose your preferred units")

            VStack(spacing: 0) {
                unitRow("Weight", detail: "Used for body weight tracking") {
                    PillSegmentedPicker(
                        options: WeightUnit.allCases,
                        selection: $weightUnit,
                        label: { $0.symbol }
                    )
                    .fixedSize()
                }

                unitRow("Temperature", detail: "Used for skin temperature readings") {
                    PillSegmentedPicker(
                        options: TemperatureUnit.allCases,
                        selection: $temperatureUnit,
                        label: { $0.symbol }
                    )
                    .fixedSize()
                }
            }
            .ruled(.top)
        } actions: {
            Button("Continue") {
                phase = .diet
            }
            .buttonStyle(NotebookPrimaryButtonStyle())
        }
    }

    private func unitRow<Picker: View>(_ title: String, detail: String, @ViewBuilder picker: () -> Picker) -> some View {
        // At accessibility text sizes the picker moves under the label
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Notebook.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            picker()
        }
        .padding(.vertical, 12)
        .ruled()
    }

    // MARK: - Diet Setup

    @State private var selectedDietType: DietTypeOption?

    private var dietSetupView: some View {
        page(step: 3) {
            pageTitle("Your Diet", subtitle: "What best describes how you eat?")

            // Diet type list (top 6)
            let topDiets: [DietTypeOption] = [.mediterranean, .keto, .vegan, .vegetarian, .paleo, .intermittentFasting]
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(topDiets, id: \.self) { diet in
                        dietRow(diet)
                    }
                }
                .ruled(.top)

                Text("And more options available in Settings")
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
                    .padding(.top, 12)
            }
        } actions: {
            Button("Continue") {
                if let diet = selectedDietType {
                    let plan = DietPlan(
                        name: diet.rawValue,
                        dietType: diet.rawValue,
                        startDate: Date()
                    )
                    modelContext.insert(plan)
                }
                phase = .chat
            }
            .buttonStyle(NotebookPrimaryButtonStyle())

            if selectedDietType == nil {
                textButton("Skip — I'll set this up later") { phase = .chat }
            }
        }
    }

    private func dietRow(_ diet: DietTypeOption) -> some View {
        let isSelected = selectedDietType == diet
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDietType = isSelected ? nil : diet
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: diet.iconName)
                    .font(.body)
                    .foregroundStyle(Notebook.ink)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(diet.rawValue)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NotebookCheckbox(isOn: isSelected)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Chat Setup

    @State private var apiKeyInput = ""
    @State private var consentAcknowledged = false
    @State private var providerReady = false

    private var hasProviderKey: Bool {
        AIKeyStore.value(for: aiProvider) != nil
    }

    private var chatSetupView: some View {
        page(step: 4) {
            pageTitle(
                "Optional AI Health Chat",
                subtitle: "Ask about your own records or import a lab report. Aura is still fully usable without AI."
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("Provider").kicker()
                PillSegmentedPicker(
                    options: AIProvider.allCases,
                    selection: $aiProvider,
                    label: { $0.displayName }
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                chatCapability(icon: "doc.text.magnifyingglass", text: "Review PDF and image lab reports before saving")
                chatCapability(icon: "chart.line.uptrend.xyaxis", text: "Ask about vitals, trends, and summaries")
                chatCapability(icon: "square.and.pencil", text: "Log measurements, medications, and habits")
            }
            .ruled(.top)

            if providerReady {
                HStack(alignment: .firstTextBaseline) {
                    Text(aiProvider.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Notebook.ink)
                    Spacer()
                    StatusWord(text: "ready", color: Notebook.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(aiProvider.displayName) is ready")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !hasProviderKey {
                        SecureField(aiProvider.keyPlaceholder, text: $apiKeyInput)
                            .textContentType(.password)
                            .font(Notebook.mono(.callout))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Notebook.paperRaised, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Notebook.rule, lineWidth: 1))
                    }

                    Toggle("I allow AI processing", isOn: $consentAcknowledged)
                        .foregroundStyle(Notebook.ink)

                    Text("When you explicitly send a message or attachment, Aura shares that content and health records returned by its read tools for that request with \(aiProvider.displayName). Nothing is sent automatically.")
                        .font(.footnote)
                        .foregroundStyle(Notebook.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: aiProvider.privacyPolicyURL) {
                        Text("Read \(aiProvider.displayName)'s privacy policy")
                            .font(.footnote)
                            .underline()
                            .foregroundStyle(Notebook.ink)
                    }

                    Button("Save and Enable AI") {
                        saveAISetup()
                    }
                    .buttonStyle(NotebookSecondaryButtonStyle())
                    .disabled(!consentAcknowledged || (!hasProviderKey && apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        } actions: {
            Button("Finish Setup") {
                hasCompletedOnboarding = true
            }
            .buttonStyle(NotebookPrimaryButtonStyle())

            if !providerReady {
                textButton("Skip AI for Now") { hasCompletedOnboarding = true }
            }
        }
        .onAppear {
            refreshAISetupState()
        }
        .onChange(of: aiProvider) {
            aiModelID = AIProviderCatalog.defaultModelID(for: aiProvider)
            apiKeyInput = ""
            consentAcknowledged = false
            refreshAISetupState()
        }
    }

    private func saveAISetup() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard AIKeyStore.setValue(trimmed, for: aiProvider) else { return }
        }
        AIConsentStore().grant(for: aiProvider)
        apiKeyInput = ""
        providerReady = true
    }

    private func refreshAISetupState() {
        providerReady = AIKeyStore.value(for: aiProvider) != nil
            && AIConsentStore().hasConsent(for: aiProvider)
        if !providerReady {
            consentAcknowledged = false
        }
    }

    private func chatCapability(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Notebook.ink)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(.callout)
                .foregroundStyle(Notebook.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .ruled()
    }

    // MARK: - Shared Components

    private func integrationButton(icon: String, title: String, subtitle: String, connected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Notebook.ink)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Notebook.ink)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Notebook.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                if connected {
                    StatusWord(text: "requested")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Notebook.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .ruled(.top)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(connected)
    }
}
