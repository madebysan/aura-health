# Changelog

## Unreleased

### Changed

- Narrowed Aura to an iPhone-only iOS 17+ release.
- Replaced CloudKit-backed storage with a non-destructive local SwiftData container.
- Expanded backups and restores to include all user-owned records with stable identifiers.
- Added duplicate-safe merge, destructive replace, and truthful complete-data deletion flows.
- Added Anthropic and OpenRouter as optional user-key AI providers.
- Added provider-specific AI consent, revocation, capability-gated attachments, and safer error handling.
- Limited HealthKit to necessary read access and clarified system-controlled permissions.
- Reframed biomarker and AI language as educational rather than diagnostic or treatment guidance.

### Added

- Unit tests for backup, restore, deletion, local storage, AI consent, and OpenRouter transport formats.
- An in-app privacy and support view.
- A privacy manifest covering Aura's UserDefaults access.
- App Store metadata, reviewer notes, guarded Fastlane lanes, and current iPhone screenshots.
- `PRIVACY.md`, `SUPPORT.md`, and `DESIGN.md` release documentation.

### Removed

- CloudKit and iCloud entitlements.
- Native macOS and iPad target support.
- Clinical Health Records, direct FHIR, WHOOP, and Health Auto Export release scope.
- Automatic AI-generated daily protocol behavior.
