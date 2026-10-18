# Changelog

## Unreleased

### Changed

- Adopted the Notebook visual direction across the app: ink on paper, SF Mono for numbers and labels, hairline rules instead of cards, one signal color plus amber for near-limit results, and status always written as a word. Every sheet and form uses the same Notebook form style.
- Biomarker status now reads "In range", "Near limit", "Above range" or "Below range". Results just outside a range are shown in amber instead of red, and a lab minimum of 0 means there is no lower limit.
- Biomarkers opens each past lab session with that session's own values; it used to show the latest value instead.
- Range bars put their limit labels at the band edges and skip the meaningless "too low" zone for upper-only ranges such as LDL.
- Vitals rows show a status word and arrow instead of a color-only dot, readings older than 7 days show "Last logged", and every note is listed with its own Dismiss.
- Vitals, Biomarkers, Habits and their sheets scale or stack at accessibility text sizes; charts and habit day cells have VoiceOver labels and spoken summaries.
- Sample data fills each empty area on its own, so an Apple Health sync no longer blocks habits, labs and the rest. It now includes example chat threads, and Settings asks before loading it.
- Blood pressure charts draw systolic and diastolic as separate lines.
- Deleting a diet plan asks for confirmation.
- Replaced SF Symbols with Phosphor Light icons throughout the app. Fruits no longer uses the Apple logo.

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
