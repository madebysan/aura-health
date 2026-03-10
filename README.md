<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon">
</p>
<h1 align="center">Aura</h1>
<p align="center">A personal health tracking app that aggregates data from WHOOP, Apple Health, and manual entries into one place.</p>
<p align="center"><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+ · Apple Silicon & Intel</p>

---

## Features

- **Vitals Dashboard** — daily health score ring (8-metric weighted calculation), sparkline cards for each metric, insight card stack with swipe-to-dismiss
- **Tracking** — daily habit grid with time-of-day sections, adherence heatmaps (60 days), streak tracking
- **Correlations** — visualize relationships between metrics over time
- **Biomarkers** — track lab results with reference ranges, status summary bar, import from lab reports (local parsing + Claude API fallback)
- **Medications** — log prescriptions, supplements, and OTC with timing and frequency
- **Conditions** — track health conditions with status (active, managed, resolved)
- **Diet** — diet type selection with food category tracking
- **Vault** — store health documents (PDFs, images, text); auto-saves chat attachments
- **AI Chat** — Claude-powered health assistant with tool use (reads/writes vitals, biomarkers, medications), conversation history, floating chat button (⌘K), API key gating
- **Onboarding** — feature highlights, integration setup, unit preferences, diet selection, API key setup
- **Import/Export** — JSON backup and restore of all data

## Integrations

| Source | Status | Data Pulled |
|--------|--------|-------------|
| **WHOOP** | Coming Soon | Recovery, HRV, resting HR, SpO2, skin temp, sleep score, sleep duration, strain, calories, weight |
| **Apple Health** | HealthKit authorized (iOS only) | Steps, heart rate, weight, blood pressure, SpO2, temperature, calories, HRV, exercise minutes, sleep |
| **Manual Entry** | Always available | All metric types |
| **CSV Import** | Always available | All metric types |

## Tech Stack

- **Language:** Swift 5.9
- **UI:** SwiftUI (universal — iOS + macOS via Catalyst-free approach)
- **Data:** SwiftData (on-device persistence)
- **Auth:** ASWebAuthenticationSession (WHOOP OAuth)
- **Health:** HealthKit (iOS only)
- **AI:** Claude API via direct REST calls
- **Secrets:** Keychain (API keys, OAuth tokens)
- **Project generation:** XcodeGen (`project.yml`)

## Project Structure

```
AuraHealth/
  App/            — App entry point, design system tokens
  Data/           — Biomarker reference data
  Enums/          — All enums (metric types, sources, units, etc.)
  Models/         — SwiftData models (Measurement, Medication, Habit, etc.)
  Services/       — WhoopService, HealthKitService, ClaudeService, KeychainService, ImportExportService
  Views/          — Organized by feature (Today, Trends, Biomarkers, Chat, Settings, etc.)
  Resources/      — App icon and asset catalog
```

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd aura-swift
xcodegen generate
open AuraHealth.xcodeproj
```

Build for macOS or iOS from Xcode, or from CLI:

```bash
# macOS
xcodebuild -project AuraHealth.xcodeproj -scheme AuraHealth -destination 'platform=macOS' build

# iOS Simulator
xcodebuild -project AuraHealth.xcodeproj -scheme AuraHealth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Known Limitations

- **WHOOP** — OAuth flow implemented but disabled ("Coming Soon"). Needs app registration at developer.whoop.com with redirect URI `aurahealth://whoop/callback`. Code is ready in `WhoopService.swift`.
- **Apple Health (macOS)** — HealthKit is iOS-only. macOS uses Health Auto Export (iCloud Drive relay) as an alternative via `HealthAutoExportService`.

### Backlog
- [ ] Register WHOOP developer app and enable OAuth integration
- [ ] Test Apple Health sync on real iOS device
- [ ] Auto-sync on app launch with background refresh (iOS)
- [ ] Add Oura Ring integration
- [ ] Add Garmin integration
- [ ] iPad-specific layouts

---

<p align="center">Made by <a href="https://santiagoalonso.com">santiagoalonso.com</a></p>
