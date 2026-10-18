import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Label("Health records stay in Aura's local database.", image: "ph.device-mobile")
                Label("Aura does not use analytics, advertising, or tracking SDKs.", image: "ph.hand")
                Label("Backups are created only when you explicitly export one.", image: "ph.export")
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
                Text("The assistant uses Apple's on-device model and sends nothing anywhere. Cloud AI is optional: it stays off until you choose Anthropic or OpenRouter, add your own API key, and allow processing. Then, when you explicitly send a message or attachment, Aura shares that content and health records returned by its read tools for that request with the selected provider. Nothing is sent automatically.")

                Link("Anthropic Privacy Policy", destination: AIProvider.anthropic.privacyPolicyURL)
                Link("OpenRouter Privacy Policy", destination: AIProvider.openRouter.privacyPolicyURL)
            } header: {
                Text("Assistant").kicker()
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

// MARK: - Acknowledgements

/// Third-party notices Aura must ship. Phosphor's MIT license requires its
/// copyright and permission notice in copies of the icons.
struct AcknowledgementsView: View {
    private static let phosphorLicense = """
    MIT License

    Copyright (c) 2023 Phosphor Icons

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Icons").kicker()
                Text("Phosphor Icons, light weight")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                Link("phosphoricons.com", destination: URL(string: "https://phosphoricons.com")!)
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
                Text(Self.phosphorLicense)
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .notebookBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
