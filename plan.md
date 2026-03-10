# Aura Health — Session Handoff

## Last session: 2026-03-09

### Done this session (2 sessions combined)

**Navigation & Structure**
- Renamed "Today" tab to "Tracking" across the app
- Made Vitals the default tab (was Today)
- Reordered tab bar: Vitals, Tracking, Biomarkers, Chat
- Changed biomarkers icon from flask to blood drop (`drop.fill`)
- Hide tab bar when drilling down from "More" menu into secondary pages

**Vitals Dashboard**
- Expanded Daily Health Score from 3 metrics to 8 weighted metrics (recovery, sleepScore, hrv, heartRate, sleepDuration, steps, activeMinutes, spo2) — works with Apple Health alone, not just WHOOP
- Dynamic "Based on..." contributor text below the score
- Insight cards: WHOOP-style stacked card deck with swipe-to-dismiss + close "x" button
- Auto-only metrics (activeMinutes, recovery, strain, sleepScore) hidden from grid when no data exists

**Tracking**
- Today column visually distinct from previous days (70% opacity on non-today columns)
- Adherence heatmap: full-width layout using GeometryReader, 60 days, bigger cells

**Biomarkers**
- Fixed centering of count text in status summary bar segments
- Changed trend chart line from blue to grey (less visual noise with colored status dots)

**Chat**
- Disabled input without API key — shows tappable prompt that opens API key dialog
- Added "Done" toolbar button (iOS) to dismiss keyboard
- Chat attachments auto-saved to Vault with tags (`chat-attachment`, `lab-report` for PDFs)

**Medications**
- Changed type picker from segmented control to dropdown (was cramped on iPhone)

**Onboarding**
- Added diet selection step (top 6 options + "and more" hint)
- WHOOP disabled with "Coming Soon" badge

**Settings**
- Renamed: "Export Aura Data", "Import Aura Data", "Import Biomarkers"
- Moved "Clear All Data" from Developer to Data section
- All integration icons now blue (WHOOP, Apple Health, Claude API)
- WHOOP section replaced with "Coming Soon" badge (no more credentials UI)
- Removed "Remove Credentials" from unconnected WHOOP state

### Current state
- Build: passing (iOS + macOS)
- App installed on Santiago's iPhone (iPhone 17 Pro, device ID: CFC63A02-476D-534D-A1FC-815D2D8EF980)
- Bundle ID: `com.santiagoalonso.aurahealth`
- No GitHub repo — local only

### Next steps
- [ ] Register WHOOP developer app at developer.whoop.com, configure redirect URI, re-enable OAuth
- [ ] Test Apple Health sync on real device
- [ ] Visual QA pass (`/visual-qa-swift`) across all screens
- [ ] UI polish pass (`/swift-ui-polish`) for animations and micro-interactions
- [ ] App icon design
- [ ] TestFlight build prep

### Key files modified
- `ContentView.swift` — navigation restructure, tab bar hiding on drill-down
- `TodayView.swift` — health score expansion, insight card stack, auto-only metric filtering
- `HabitsView.swift` — tracking rename, day column opacity
- `AdherenceView.swift` — full-width heatmap rewrite
- `BiomarkersView.swift` — status bar centering, chart line color
- `ChatView.swift` — API key gating, keyboard dismiss, vault integration
- `MedicationsView.swift` — type picker change
- `OnboardingView.swift` — diet step, WHOOP coming soon
- `SettingsView.swift` — label renames, icon colors, WHOOP coming soon, data section reorg
- `MetricCardView.swift` — activeMinutes delta color logic (unchanged but referenced)
