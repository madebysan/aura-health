<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon">
</p>
<h1 align="center">Aura</h1>
<p align="center">Your vitals. Your labs. Your data.<br>
A health dashboard that connects your vitals, labs, and habits in one place.</p>
<p align="center"><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+</p>

---

<p align="center">
  <img src="assets/screenshots.png" width="100%" alt="Aura app screenshots">
</p>

## What it does

Aura pulls data from Apple Health, manual entries, and lab reports into a single dashboard. The built-in AI chat isn't just for questions — it can retrieve your latest vitals, log new measurements, update medications, and extract biomarkers from attached lab report photos and PDFs. You can manage most of your health data without leaving the conversation. Everything stays on your device.

## Features

### Vitals Dashboard
Track heart rate, HRV, blood pressure, sleep, steps, weight, SpO2, skin temperature, calories, and more. Each metric gets a sparkline card with delta indicators, reference ranges, and educational context explaining what the numbers mean and why they matter. Filter by Today, 7d, 30d, 90d, 1y, or All. A composite Daily Health Score summarizes your overall readiness.

### Habits
Daily habit grid organized by time of day (morning, afternoon, evening, night). Supports boolean and quantity tracking. Includes streak counts, adherence heatmaps, and drag-and-drop reordering. AI-generated smart habits based on your actual health data.

### Biomarkers
Lab results viewer with 40+ markers grouped by body system (Heart, Metabolic, Liver, Kidney, Thyroid, etc.). Each marker shows status (Normal, Borderline, Abnormal), reference ranges, and plain-English descriptions. Supports multiple lab sessions with date-based snapshots. Import lab reports by attaching a PDF or photo to the AI chat.

### AI Chat
Claude-powered health assistant with full tool use — it can read and write your vitals, biomarkers, medications, and habits. Supports 60+ biomarker aliases (e.g., "LDL", "A1C", "TSH"). Attach PDFs or photos for lab report extraction.

### Medications
Log prescriptions, supplements, and OTC medications with dosage, timing (AM fasted, with food, bedtime), and frequency. Filter by type.

### Correlations
Scatter plots with Pearson correlation coefficients between metric pairs — Sleep Score vs Recovery, HRV vs Strain, Sleep Duration vs Resting HR, and more. Filterable by time range.

### Conditions
Track health conditions (diabetes, hypertension, anxiety, etc.) with status tracking: Active, Managed, or Resolved. Autocomplete from 70+ common conditions.

### Diet
Choose a diet type (Mediterranean, Keto, Paleo, etc.) with pre-populated approved and avoided food categories. Customizable per plan.

### Vault
Secure document storage for health files — PDFs, images, text files. Auto-saves chat attachments. Photos saved from chat get smart titles based on conversation context.

### Settings
Unit preferences (kg/lbs, C/F), Apple Health connection with sync, Claude API key and model selection (Haiku, Sonnet, Opus), data import/export.

---

## Integrations

| Source | Status | Data |
|--------|--------|------|
| **Apple Health** | HealthKit (iOS) | Steps, heart rate, weight, blood pressure, SpO2, temperature, calories, HRV, exercise minutes, sleep |
| **Manual Entry** | Always available | All metric types, biomarkers, medications, habits |
| **Lab Reports** | Via Chat (PDF/image) | Biomarkers extracted by Claude |
| **JSON Import** | Always available | Full data backup and restore |

## Tech Stack

- **Swift 5.9** — SwiftUI for all views (universal iOS + macOS)
- **SwiftData** — on-device persistence with CloudKit sync
- **HealthKit** — Apple Health integration (iOS only)
- **Claude API** — AI chat with tool use via direct REST calls
- **Keychain** — API keys stored securely at runtime
- **XcodeGen** — project generation from `project.yml`

## Project Structure

```
AuraHealth/
  App/            — App entry point, design system tokens
  Data/           — Biomarker reference data (40+ markers)
  Enums/          — All enums (metric types, sources, units, etc.)
  Models/         — SwiftData models (Measurement, Medication, Habit, etc.)
  Services/       — HealthKit, Claude, Keychain, Import/Export, FHIR, etc.
  Views/          — Organized by feature (Vitals, Habits, Biomarkers, Chat, etc.)
  Resources/      — App icon and asset catalog
```

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd aura
xcodegen generate
open AuraHealth.xcodeproj
```

Build for macOS or iOS from Xcode, or from CLI:

```bash
# iOS Simulator
xcodebuild -scheme AuraHealth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# macOS
xcodebuild -scheme AuraHealth -destination 'platform=macOS' build
```

## Setup

1. Clone the repo and run `xcodegen generate`
2. Build and run on an iOS device or simulator
3. Grant Apple Health permissions when prompted
4. Add your Claude API key in **Settings → AI** to enable chat features

## Notes

- **Apple Health on macOS** — HealthKit is iOS-only. macOS uses Health Auto Export (iCloud Drive relay) as a workaround.
- **CloudKit Sync** — Data syncs across devices via iCloud automatically through SwiftData's CloudKit integration.
- **No server** — Everything runs on-device. The only network calls are to the Claude API (your own key) and Apple Health.

---

## Privacy & Security

- **On-device storage** — All health data is stored locally using SwiftData. Nothing is uploaded to any server.
- **No accounts** — There are no user accounts, no sign-ups, no analytics, no tracking.
- **iCloud sync** — Data syncs between your devices via CloudKit, encrypted by Apple. No third-party cloud involved.
- **Your API key** — The Claude AI chat uses your own API key, stored in the iOS Keychain. Aura never sees or stores your key on any server.
- **What gets sent to Claude** — When you use the chat, your message and relevant health context (recent vitals, biomarkers, medications) are sent to the Claude API. This is a direct call from your device to Anthropic — Aura has no backend in between.
- **No telemetry** — Zero analytics, crash reporting, or usage tracking of any kind.

## License

This project is licensed under the [MIT License](LICENSE).

---

<p align="center">Made by <a href="https://santiagoalonso.com">santiagoalonso.com</a></p>
