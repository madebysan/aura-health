# Aura Health — Session Handoff

## Last session: 2026-03-09

### Done this session (3 sessions combined)

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
- Removed insight count badge — only X close button remains
- Insight background cards now show actual content (next card's text visible during swipe) instead of empty material shells
- Stacked card spacing tightened (6px → 4px)
- Metric grid sorts cards with data to top, empty cards pushed to bottom

**Tracking**
- Today column visually distinct from previous days (50% opacity on non-today columns)
- Adherence heatmap: full-width layout using GeometryReader, 60 days, bigger cells
- Fixed heatmap clipping — uses `aspectRatio` instead of fixed height
- Fixed streak calculation to check consecutive calendar days from today (was counting all consecutive done logs regardless of gaps)

**Biomarkers**
- Fixed centering of count text in status summary bar segments
- Changed trend chart line from blue to grey (less visual noise with colored status dots)
- Empty state redesigned: primary CTA "Upload Lab Results in Chat" (switches to Chat tab), secondary "Add Biomarker Manually"

**Chat**
- Disabled input without API key — shows tappable prompt that opens API key dialog
- Added "Done" toolbar button (iOS) to dismiss keyboard
- Chat attachments auto-saved to Vault with tags (`chat-attachment`, `lab-report` for PDFs)

**Medications**
- Changed type picker from segmented control to dropdown (was cramped on iPhone)

**Onboarding**
- Added diet selection step — vertical list with checkmark indicator, top 6 options + "and more" hint
- WHOOP badge shortened to "Soon" (was "Coming Soon")

**Settings**
- Renamed: "Export Aura Data", "Import Aura Data", "Import Biomarkers"
- Moved "Clear All Data" from Developer to Data section
- All integration icons now blue (WHOOP, Apple Health, Claude API)
- WHOOP section replaced with "Coming Soon" badge (no more credentials UI)
- Removed "Remove Credentials" from unconnected WHOOP state
- Disconnect Apple Health icon now red (matches destructive role)

**Apple Health**
- Fixed weight not syncing — added `syncLatestSample()` that fetches the most recent sample with no date restriction, solving the issue where weight entries older than 30 days were missed
- Added `.switchToChat` notification for cross-tab navigation from Biomarkers empty state

### Current state
- Build: passing (iOS + macOS)
- App installed on Santiago's iPhone (iPhone 17 Pro, device ID: CFC63A02-476D-534D-A1FC-815D2D8EF980)
- Bundle ID: `com.santiagoalonso.aurahealth`
- No GitHub repo — local only

### Next steps
- [ ] Register WHOOP developer app at developer.whoop.com, configure redirect URI, re-enable OAuth
- [ ] Verify weight + other sparse metrics loading after Apple Health sync
- [ ] Visual QA pass (`/visual-qa-swift`) across all screens
- [ ] UI polish pass (`/swift-ui-polish`) for animations and micro-interactions
- [ ] App icon design
- [ ] TestFlight build prep

### Key files modified
- `ContentView.swift` — navigation restructure, tab bar hiding, switchToChat handler
- `TodayView.swift` — health score, insight cards (content on background, no badge, tighter spacing), metric sorting
- `HabitsView.swift` — tracking opacity 50%, streak fix, heatmap no-clip
- `AdherenceView.swift` — full-width heatmap with aspectRatio sizing
- `BiomarkersView.swift` — status bar centering, chart line color, empty state with Chat CTA
- `ChatView.swift` — API key gating, keyboard dismiss, vault integration
- `MedicationsView.swift` — type picker change
- `OnboardingView.swift` — diet vertical list, "Soon" badge
- `SettingsView.swift` — label renames, icon colors, red disconnect icon, WHOOP coming soon
- `HealthKitService.swift` — syncLatestSample() for sparse metrics like weight
- `AuraHealthApp.swift` — added switchToChat notification name
