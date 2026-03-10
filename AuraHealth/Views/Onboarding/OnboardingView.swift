import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WhoopService.self) private var whoopService
    @Environment(HealthKitService.self) private var healthKitService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("temperatureUnit") private var temperatureUnit: TemperatureUnit = .celsius

    @State private var phase: OnboardingPhase = .welcome

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
    }

    // MARK: - Welcome (Mock Data Prompt)

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)

            VStack(spacing: 8) {
                Text("Welcome to Aura")
                    .font(.largeTitle.bold())
                Text("Your personal health companion")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Want to explore with sample data?")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Button {
                    SampleDataService.loadSampleData(into: modelContext)
                    hasCompletedOnboarding = true
                } label: {
                    Text("Load Sample Data")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    phase = .features
                } label: {
                    Text("Set Up My Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Feature Highlights

    @State private var featurePage = 0

    private let features: [(icon: String, color: Color, title: String, description: String)] = [
        (
            "heart.text.square.fill",
            .pink,
            "Track Your Vitals",
            "Monitor heart rate, HRV, sleep, recovery, and more — all in one place. See trends over time with clear charts."
        ),
        (
            "cross.vial.fill",
            .green,
            "Lab Results & Biomarkers",
            "Import your blood work and track biomarkers across tests. Spot trends your doctor might miss."
        ),
        (
            "bubble.left.and.bubble.right.fill",
            .cyan,
            "AI Health Chat",
            "Ask questions about your health data. Get personalized insights powered by Claude."
        ),
    ]

    private var featuresView: some View {
        VStack(spacing: 0) {
            TabView(selection: $featurePage) {
                ForEach(0..<features.count, id: \.self) { index in
                    featureCard(features[index])
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            Button {
                if featurePage < features.count - 1 {
                    withAnimation { featurePage += 1 }
                } else {
                    phase = .connect
                }
            } label: {
                Text(featurePage < features.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.bottom, 32)

            if featurePage < features.count - 1 {
                Button("Skip") {
                    phase = .connect
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
            }
        }
    }

    private func featureCard(_ feature: (icon: String, color: Color, title: String, description: String)) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: feature.icon)
                .font(.system(size: 64))
                .foregroundStyle(feature.color)

            VStack(spacing: 12) {
                Text(feature.title)
                    .font(.title.bold())

                Text(feature.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Connect Integrations

    private var connectView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("Connect Your Data")
                    .font(.largeTitle.bold())
                Text("Link a data source to get started")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                // WHOOP (Coming Soon)
                comingSoonIntegration(
                    icon: "heart.circle.fill",
                    title: "Connect WHOOP",
                    subtitle: "Sync recovery, sleep, strain & more"
                )

                // Apple Health
                #if os(iOS)
                integrationButton(
                    icon: "heart.text.square",
                    color: .red,
                    title: "Connect Apple Health",
                    subtitle: healthKitService.isAuthorized ? "Connected" : "Sync workouts, steps, heart rate & more",
                    connected: healthKitService.isAuthorized
                ) {
                    Task { await healthKitService.requestAuthorization() }
                }
                #endif
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    phase = .preferences
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    phase = .preferences
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: - Preferences (Units)

    private var preferencesView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "gearshape.fill")
                .font(.system(size: 64))
                .foregroundStyle(.gray)

            VStack(spacing: 8) {
                Text("Your Preferences")
                    .font(.title.bold())
                Text("Choose your preferred units")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 20) {
                // Weight unit
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight")
                            .font(.headline)
                        Text("Used for body weight tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Weight", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                Divider()

                // Temperature unit
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temperature")
                            .font(.headline)
                        Text("Used for skin temperature readings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Temperature", selection: $temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .padding(20)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()

            Button {
                phase = .diet
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: - Diet Setup

    @State private var selectedDietType: DietTypeOption?

    private var dietSetupView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "fork.knife")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Your Diet")
                    .font(.title.bold())
                Text("What best describes how you eat?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Diet type grid (top 6)
            let topDiets: [DietTypeOption] = [.mediterranean, .keto, .vegan, .vegetarian, .paleo, .intermittentFasting]
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(topDiets, id: \.self) { diet in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDietType = (selectedDietType == diet) ? nil : diet
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: diet.iconName)
                                .font(.system(size: 14))
                                .foregroundStyle(selectedDietType == diet ? .white : diet.color)
                                .frame(width: 20)
                            Text(diet.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(selectedDietType == diet ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            selectedDietType == diet ? diet.color : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)

            Text("And more options available in Settings")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if let diet = selectedDietType {
                        let plan = DietPlan(
                            name: diet.rawValue,
                            dietType: diet.rawValue,
                            startDate: Date()
                        )
                        modelContext.insert(plan)
                    }
                    phase = .chat
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                if selectedDietType == nil {
                    Button {
                        phase = .chat
                    } label: {
                        Text("Skip — I'll set this up later")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: - Chat Setup (API Key)

    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false

    private var hasExistingKey: Bool {
        KeychainService.getValue(for: "claude-api-key") != nil
    }

    private var chatSetupView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)

            VStack(spacing: 12) {
                Text("AI Health Chat")
                    .font(.title.bold())

                Text("Chat can answer questions about your vitals, interpret lab reports, log measurements, and spot trends — all powered by Claude.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Capabilities list
            VStack(alignment: .leading, spacing: 12) {
                chatCapability(icon: "doc.text.magnifyingglass", color: .green, text: "Attach a PDF lab report and import biomarkers automatically")
                chatCapability(icon: "chart.line.uptrend.xyaxis", color: .pink, text: "Ask about your vitals, trends, and health summary")
                chatCapability(icon: "square.and.pencil", color: .orange, text: "Log measurements, medications, and habits by chat")
            }
            .padding(.horizontal, 32)

            Spacer()

            // API Key input
            if apiKeySaved || hasExistingKey {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("API key configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    Text("Enter your Claude API key to enable chat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            if !apiKeyInput.isEmpty {
                                KeychainService.setValue(apiKeyInput, for: "claude-api-key")
                                apiKeyInput = ""
                                apiKeySaved = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.isEmpty)
                    }
                }
                .padding(.horizontal, 40)
            }

            VStack(spacing: 12) {
                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Finish Setup")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                if !apiKeySaved && !hasExistingKey {
                    Button {
                        hasCompletedOnboarding = true
                    } label: {
                        Text("Skip — I'll add it later in Settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .padding()
    }

    private func chatCapability(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Shared Components

    private func comingSoonIntegration(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("Coming Soon")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private func integrationButton(icon: String, color: Color, title: String, subtitle: String, connected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(connected)
    }
}
