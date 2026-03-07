<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon">
</p>
<h1 align="center">Aura</h1>
<p align="center">A personal health tracking app that aggregates data from WHOOP, Apple Health, and manual entries into one place.</p>
<p align="center"><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+ · Apple Silicon & Intel</p>

---

## Features

- **Vitals Dashboard** — daily health score ring, sparkline cards for each metric, detail sheets
- **Correlations** — visualize relationships between metrics over time
- **Biomarkers** — track lab results with reference ranges, import from lab reports (local parsing + Claude API fallback)
- **Medications** — log prescriptions, supplements, and OTC with timing and frequency
- **Habit Tracking** — boolean and quantity-based habits with daily logging
- **Conditions** — track health conditions with status (active, managed, resolved)
- **Vault** — store health documents (PDFs, images, text)
- **AI Chat** — Claude-powered health assistant with tool use (reads/writes vitals, biomarkers, medications), conversation history, floating chat button (⌘K)
- **Import/Export** — JSON backup and restore of all data

## Integrations

| Source | Status | Data Pulled |
|--------|--------|-------------|
| **WHOOP** | OAuth 2.0 connected | Recovery, HRV, resting HR, SpO2, skin temp, sleep score, sleep duration, strain, calories, weight |
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

## Outstanding Issues

### WHOOP Sync (400 Error)
- OAuth connection works, but data sync returns a 400 error
- The `limit` parameter was reduced from 30 to 25 (WHOOP's max), but the error persists
- Needs further investigation — may be a different query parameter or API version issue
- **Workaround:** None yet. WHOOP data can be manually entered in the meantime.

### Apple Health (macOS)
- HealthKit is **not available on macOS** — this is an Apple platform limitation, not a bug
- Apple Health integration works on iOS only (iPhone, iPad)
- The app correctly shows "Not Available" on Mac

### Apple Health on macOS — Options to Investigate

HealthKit is iOS-only. Two viable paths to get Apple Health data on the Mac:

**Option A: Mac Catalyst (recommended)**
Convert the macOS target from "My Mac" to "Mac (Designed for iPad)". Existing HealthKit code works as-is. Near real-time data via iCloud Health sync. Free. Tradeoff: app UI becomes more iPad-on-Mac, less native macOS feel.

**Option B: Health Auto Export (relay app)**
Third-party iPhone app that auto-pushes Health data to Mac via iCloud Drive (JSON) or local REST endpoint. Keeps the app fully native macOS. Tradeoff: requires a separate paid app on iPhone, data lags by minutes.

Not viable: Third-party APIs (Terra, Vital — $399+/mo enterprise pricing), Apple REST API (doesn't exist), iCloud direct access (encrypted, no API), Shortcuts (unreliable), CareKit/ResearchKit (iOS only), manual XML export (tedious).

### Backlog
- [ ] Fix WHOOP sync 400 error (investigate exact failing endpoint)
- [ ] Decide on Apple Health macOS approach (Mac Catalyst vs Health Auto Export relay)
- [ ] Test Apple Health sync on iOS device or simulator with sample health data
- [ ] Add WHOOP pagination (currently fetches only 25 most recent per category)
- [ ] Auto-sync on app launch with background refresh (iOS)
- [ ] Token expiry handling — proactively refresh before expiry instead of waiting for 401
- [ ] Add Oura Ring integration
- [ ] Add Garmin integration

---

<p align="center">Made by <a href="https://santiagoalonso.com">santiagoalonso.com</a></p>
