<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon">
</p>
<h1 align="center">Aura Health</h1>
<p align="center">Health dashboard for your vitals, labs, habits, and the conversations about them.<br>
Built for people who read their own lab reports.</p>
<p align="center"><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+</p>

---

<p align="center">
  <img src="assets/screenshots.png" width="100%" alt="Aura app screenshots across iOS and macOS">
</p>

---

Most health tracking apps are either too clinical or too mood-driven. I wanted one that respected both the data and the person reading it. Before Aura I was logging my biomarkers, habits, and health notes in a spreadsheet that quickly became unmanageable. I turned it into a webapp first, then realized I wanted better integration with Apple Health and wearables, so I refactored it in Swift for both iOS and macOS.

It's for anyone who needs to track and manage their biomarkers or specific health conditions and wants to centralize all the information in a place they own without giving it away to third parties.

<div align="center">

https://github.com/user-attachments/assets/d81e0380-41ab-45e5-b22e-92e15c38edad

</div>

## What's in it

### Vitals dashboard
Your day in a single view. Heart rate, HRV, blood pressure, sleep, steps, weight, SpO2, skin temperature, calories, and more. Each metric gets a sparkline card with delta indicators, reference ranges, and a short plain-English note on what the number means and why it matters. Filter by Today / 7d / 30d / 90d / 1y / All. A composite Daily Health Score summarizes overall readiness.

### Habits
Daily habit grid organized by time of day (morning, afternoon, evening, night). Boolean and quantity tracking. Streak counts, adherence heatmaps, drag-and-drop reordering. Smart suggestions from your actual data.

### Biomarkers
Lab results viewer with 40+ markers grouped by body system (Heart, Metabolic, Liver, Kidney, Thyroid, and more). Each marker shows status (Normal, Borderline, Abnormal), reference ranges, and a plain-English description. Supports multiple lab sessions with date-based snapshots. Import lab reports by attaching a PDF or photo to the chat.

### Health assistant and accountability buddy
Bring your own Claude API key and use the built-in chat that can read and write your vitals, biomarkers, medications, and habits. Handles 60+ biomarker aliases (`LDL`, `A1C`, `TSH`, and more). Attach PDFs or photos and it extracts biomarkers from them.

### Medications
Prescriptions, supplements, and OTC meds with dosage, timing (AM fasted, with food, bedtime), and frequency. Filter by type. Recurrent medications are added as habits automatically.

### Correlations
Scatter plots with Pearson correlation coefficients between metric pairs. Sleep Score vs Recovery, HRV vs Strain, Sleep Duration vs Resting HR, and more. Filterable by time range. A useful way to see how seemingly unrelated activities or habits actually correlate.

### Conditions
Track active / managed / resolved health conditions. Autocomplete from 70+ common conditions.

### Diet
Pick a diet type (Mediterranean, Keto, Paleo, and more) with pre-populated approved / avoided food categories. Customizable per plan.

### Vault
Document storage for health files: PDFs, images, text. Auto-saves chat attachments. Photos from chat get smart titles based on conversation context.

### Settings
Unit preferences (kg/lbs, C/F), Apple Health connection with sync, API key and model selection, data import/export for backups.

## Integrations

| Source | Status | Data |
|--------|--------|------|
| **Apple Health** | HealthKit (iOS) | Steps, heart rate, weight, blood pressure, SpO2, temperature, calories, HRV, exercise minutes, sleep |
| **Manual entry** | Always available | All metric types, biomarkers, medications, habits |
| **Lab reports** | Via chat (PDF / image) | Biomarkers extracted by the health assistant |
| **JSON import** | Always available | Full data backup and restore |

## Privacy

Aura is designed to run without a server in the middle.

- **On-device storage.** All health data lives locally in SwiftData. Nothing is uploaded to an Aura server. There is no Aura server.
- **No accounts.** No sign-up, no analytics, no tracking.
- **iCloud sync.** Data syncs between your devices via CloudKit, encrypted by Apple. No third-party cloud.
- **Your API key.** The health assistant uses your Claude API key, stored in the iOS/macOS Keychain. Aura never sees or stores your key.
- **What goes to Claude.** When you use the chat, your message plus relevant health context (recent vitals, biomarkers, medications) goes directly from your device to the Anthropic API. No middleman.
- **No telemetry.** Zero analytics, zero crash reporting, zero usage tracking.

## Tech stack

- **Swift 5.9 + SwiftUI.** One codebase for iOS and macOS.
- **SwiftData + CloudKit.** On-device persistence with device-to-device sync.
- **HealthKit.** Apple Health integration (iOS only).
- **Claude API.** AI chat with tool use, called directly from the device.
- **Keychain.** API keys stored securely at runtime.

## Building

```bash
git clone https://github.com/madebysan/aura-health.git
cd aura-health
open AuraHealth.xcodeproj
```

Build for iOS or macOS from Xcode, or from CLI:

```bash
# iOS Simulator
xcodebuild -scheme AuraHealth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# macOS
xcodebuild -scheme AuraHealth -destination 'platform=macOS' build
```

## Setup

1. Clone the repo and open `AuraHealth.xcodeproj`
2. Build and run on an iOS device / simulator, or on macOS
3. Grant Apple Health permissions when prompted
4. Add your Claude API key in **Settings → AI** to enable the chat

## Project structure

```
AuraHealth/
  App/            # App entry point, design system tokens
  Data/           # Biomarker reference data (40+ markers)
  Enums/          # All enums (metric types, sources, units, etc.)
  Models/         # SwiftData models (Measurement, Medication, Habit, etc.)
  Services/       # HealthKit, Claude, Keychain, Import/Export, FHIR, etc.
  Views/          # Organized by feature (Vitals, Habits, Biomarkers, Chat, etc.)
  Resources/      # App icon and asset catalog
```

## Known limitations

- **Apple Health on macOS.** HealthKit is iOS-only. macOS users can route data in via Health Auto Export through iCloud Drive as a workaround, but there is no direct macOS HealthKit equivalent.
- **Biomarker extraction.** Lab report parsing depends on the quality of Claude's vision response. Low-resolution photos of paper reports, or unusual lab formats, can produce incomplete extractions. You can always edit the extracted values manually.

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/aura-health/issues).

## License

[MIT](LICENSE)

---

Made by [santiagoalonso.com](https://santiagoalonso.com)
