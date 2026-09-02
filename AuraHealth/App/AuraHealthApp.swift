import SwiftUI
import SwiftData

@main
struct AuraHealthApp: App {
    @State private var healthKitService = HealthKitService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let startupError = auraStorage.startupError {
                    StorageRecoveryView(message: startupError)
                } else if hasCompletedOnboarding {
                    ContentView()
                        .environment(healthKitService)
                } else {
                    OnboardingView()
                        .environment(healthKitService)
                }
            }
            #if DEBUG
            .task {
                guard UserDefaults.standard.bool(forKey: "ScreenshotData") else { return }
                SampleDataService.loadSampleData(into: auraStorage.container.mainContext)
                hasCompletedOnboarding = true
            }
            #endif
        }
        .modelContainer(auraStorage.container)
    }
}

private let auraStorage = AuraStorage.makeAppState()

private struct StorageRecoveryView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Your data is protected", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .padding()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let addMeasurement = Notification.Name("addMeasurement")
    static let newChat = Notification.Name("newChat")
    static let navigateTo = Notification.Name("navigateTo")
    static let switchToChat = Notification.Name("switchToChat")
    static let openMetricDetail = Notification.Name("openMetricDetail")
}
