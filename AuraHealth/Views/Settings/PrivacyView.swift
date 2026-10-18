import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Label("Health records stay in Aura's local database.", systemImage: "iphone")
                Label("Aura does not use analytics, advertising, or tracking SDKs.", systemImage: "hand.raised")
                Label("Backups are created only when you explicitly export one.", systemImage: "square.and.arrow.up")
            } header: {
                Text("On Your iPhone").kicker()
            }
            .listRowBackground(Notebook.paperRaised)

            Section {
                Text("Aura requests read-only access to the health categories shown in the app. Apple Health permissions remain under your control in Settings and the Health app. Aura does not write to Apple Health.")
            } header: {
                Text("Apple Health").kicker()
            }
            .listRowBackground(Notebook.paperRaised)

            Section {
                Text("AI is off until you choose Anthropic or OpenRouter, add your own API key, and allow processing. When you explicitly send a message or attachment, Aura shares that content and health records returned by its read tools for that request with the selected provider. Nothing is sent automatically.")

                Link("Anthropic Privacy Policy", destination: AIProvider.anthropic.privacyPolicyURL)
                Link("OpenRouter Privacy Policy", destination: AIProvider.openRouter.privacyPolicyURL)
            } header: {
                Text("Optional AI").kicker()
            }
            .listRowBackground(Notebook.paperRaised)

            Section {
                Text("You can remove each API key and revoke its AI consent in Settings. Create a complete local backup before replacing data. Clear All Data removes Aura's local records, documents, conversations, API keys, and preferences; it does not alter Apple Health.")
            } header: {
                Text("Your Controls").kicker()
            }
            .listRowBackground(Notebook.paperRaised)

            Section {
                Text("Aura is an organizational and educational wellness tool. It is not a medical device and does not diagnose, treat, or replace advice from a qualified healthcare professional.")
            } header: {
                Text("Health Information").kicker()
            }
            .listRowBackground(Notebook.paperRaised)

            Section {
                Link("Contact Support", destination: URL(string: "mailto:hi@santiagoalonso.com?subject=Aura%20Health%20Support")!)
                Link("Santiago Alonso", destination: URL(string: "https://santiagoalonso.com")!)
            } header: {
                Text("Support").kicker()
            }
            .listRowBackground(Notebook.paperRaised)
        }
        .foregroundStyle(Notebook.ink)
        .scrollContentBackground(.hidden)
        .notebookBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
