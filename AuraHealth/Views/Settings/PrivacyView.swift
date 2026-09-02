import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section("On Your iPhone") {
                Label("Health records stay in Aura's local database.", systemImage: "iphone")
                Label("Aura does not use analytics, advertising, or tracking SDKs.", systemImage: "hand.raised")
                Label("Backups are created only when you explicitly export one.", systemImage: "square.and.arrow.up")
            }

            Section("Apple Health") {
                Text("Aura requests read-only access to the health categories shown in the app. Apple Health permissions remain under your control in Settings and the Health app. Aura does not write to Apple Health.")
            }

            Section("Optional AI") {
                Text("AI is off until you choose Anthropic or OpenRouter, add your own API key, and allow processing. When you explicitly send a message or attachment, Aura shares that content and health records returned by its read tools for that request with the selected provider. Nothing is sent automatically.")

                Link("Anthropic Privacy Policy", destination: AIProvider.anthropic.privacyPolicyURL)
                Link("OpenRouter Privacy Policy", destination: AIProvider.openRouter.privacyPolicyURL)
            }

            Section("Your Controls") {
                Text("You can remove each API key and revoke its AI consent in Settings. Create a complete local backup before replacing data. Clear All Data removes Aura's local records, documents, conversations, API keys, and preferences; it does not alter Apple Health.")
            }

            Section("Health Information") {
                Text("Aura is an organizational and educational wellness tool. It is not a medical device and does not diagnose, treat, or replace advice from a qualified healthcare professional.")
            }

            Section("Support") {
                Link("Contact Support", destination: URL(string: "mailto:hi@santiagoalonso.com?subject=Aura%20Health%20Support")!)
                Link("Santiago Alonso", destination: URL(string: "https://santiagoalonso.com")!)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
