# Changelog

## Unreleased

### Changed

- Adopted the Notebook visual direction across the app: ink on paper, SF Mono for numbers and labels, hairline rules instead of cards, one signal color plus amber for near-limit results, and status always written as a word. Every sheet and form uses the same Notebook form style.
- Biomarker status now reads "In range", "Near limit", "Above range" or "Below range". Results just outside a range are shown in amber instead of red, and a lab minimum of 0 means there is no lower limit.
- Biomarkers opens each past lab session with that session's own values; it used to show the latest value instead.
- Range bars put their limit labels at the band edges and skip the meaningless "too low" zone for upper-only ranges such as LDL.
- Vitals rows show a status word and arrow instead of a color-only dot, and readings older than 7 days show "Last logged".
- Vitals, Biomarkers, Habits and their sheets scale or stack at accessibility text sizes; charts and habit day cells have VoiceOver labels and spoken summaries.
- Sample data fills each empty area on its own, so an Apple Health sync no longer blocks habits, labs and the rest. It now includes example chat threads, and Settings asks before loading it.
- Blood pressure charts draw systolic and diastolic as separate lines.
- Deleting a diet plan asks for confirmation.
- Replaced SF Symbols with Phosphor Light icons throughout the app. Fruits no longer uses the Apple logo.
- Simplified every screen after a UI audit (decision board, 2026-10-18):
  - Vitals opens with one plain sentence about what is outside your typical range, then a Flagged group and everything else. Rows only carry a status word when flagged, the "since last" line and the Notes list are gone, and the Daily health score is replaced by the sentence. Metrics without a reading in 30 days leave the list until the next one; a + button adds any measurement.
  - Time ranges moved from the top of Vitals into each metric's sheet. The sheet lists the latest 10 readings with "Show all", draws the typical band only when it fits the chart, and no longer repeats the range as a sentence.
  - Habits is one view: no Adherence tab (each habit's 30-day rate is in its edit sheet and the overall rate in the header), no per-section counts, streaks from 2 days, and no Category picker.
  - Biomarkers shows "15/16 in range · 1 flagged" without the strip and legend, and past lab reports open from a "lab reports" list instead of tabs (dates now include the year).
  - Chat has one "Set up AI" row that opens Settings, no intro paragraph, and photos attach without asking about the Vault; "Save to Vault" sits on the attachment.
  - Removed the Correlations screen. More is one ruled list. Medications lists Active and Archived without type tabs. Diet and Conditions no longer repeat their titles. Settings shows Apple Health as one row with Connect.
- Renamed the Biomarkers tab to Labs (test-tube icon) and Medications to Meds and Supplements, which no longer shows or asks for a prescription, supplement or OTC type (existing types stay in your data).
- Habit days are now done or not: a tap checks a day and another clears it, and missed days are plain empty boxes instead of slashed ones.
- Fixed links and assistant requests that should open a screen under More (such as Settings); they only switched to the More tab.

- Narrowed Aura to an iPhone-only iOS 17+ release.
- Replaced CloudKit-backed storage with a non-destructive local SwiftData container.
- Expanded backups and restores to include all user-owned records with stable identifiers.
- Added duplicate-safe merge, destructive replace, and truthful complete-data deletion flows.
- Added Anthropic and OpenRouter as optional user-key AI providers.
- Added provider-specific AI consent, revocation, capability-gated attachments, and safer error handling.
- Limited HealthKit to necessary read access and clarified system-controlled permissions.
- Reframed biomarker and AI language as educational rather than diagnostic or treatment guidance.

### Added

- Unit tests for backup, restore, deletion, local storage, AI consent, and OpenRouter transport formats, plus biomarker status rules and sample-data loading.
- An in-app privacy and support view.
- A privacy manifest covering Aura's UserDefaults access.
- App Store metadata, reviewer notes, guarded Fastlane lanes, and current iPhone screenshots.
- `PRIVACY.md`, `SUPPORT.md`, and `DESIGN.md` release documentation.

### Removed

- CloudKit and iCloud entitlements.
- Native macOS and iPad target support.
- Clinical Health Records, direct FHIR, WHOOP, and Health Auto Export release scope.
- Automatic AI-generated daily protocol behavior.
