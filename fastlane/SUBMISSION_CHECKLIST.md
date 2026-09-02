# Aura Health Submission Checklist

## Local gates

- [x] iPhone-only target (`TARGETED_DEVICE_FAMILY = 1`)
- [x] Version 1.0.0 and local build number 3
- [x] No iCloud, CloudKit, Clinical Health Records, FHIR, WHOOP, or macOS release entitlement
- [x] Local-only SwiftData startup with no automatic destructive recovery
- [x] Complete backup, duplicate-safe merge, destructive replace, and complete local deletion
- [x] Anthropic and OpenRouter provider adapters
- [x] Provider-specific Keychain storage and consent
- [x] Explicit approval for every model-requested data mutation
- [x] Privacy manifest and in-app privacy/support surface
- [x] Current 1320×2868 iPhone screenshots without alpha
- [x] Release archive and App Store IPA export

## External/manual gates

- [x] Confirm the connected primary iPhone had no existing Aura container, then install and launch build 3 cleanly
- [ ] Confirm the highest existing build and current version state in App Store Connect
- [ ] Confirm build 3 is still available; increment it if another build already exists
- [ ] Test Anthropic and OpenRouter with user-owned keys after reviewing the in-app consent flow
- [ ] Run Apple Health denied/partial/allowed, offline, invalid-key, attachment, and mutation-approval tests on the physical iPhone
- [ ] Run VoiceOver, Larger Text, Reduce Motion, and iPad compatibility-mode checks
- [x] Publish `PRIVACY.md` and `SUPPORT.md` with the approved public release commit, then verify both URLs
- [ ] Complete and publish App Privacy answers in App Store Connect
- [ ] Complete age rating, category, pricing, territories, export compliance, copyright, and content-rights fields
- [ ] Complete EU DSA trader status if EU territories are included
- [ ] Add reviewer contact phone through `APP_REVIEW_PHONE`; never commit it
- [ ] Obtain fresh approval before metadata upload, TestFlight upload, or App Review submission
- [ ] Keep manual release selected

## Conservative App Privacy draft

Verify these answers manually against the final provider behavior and current Apple definitions:

- Tracking: No
- Advertising: No
- Analytics: No
- Developer-owned account data: None
- App functionality: Health & Fitness, Sensitive Info, User Content, Photos or Videos, and Other User Content may leave the device only when the user explicitly sends them to the selected AI provider
- Data linked to the user: review conservatively because provider processing occurs under the user's provider account/API key
- Third-party processing: include Anthropic or OpenRouter and relevant upstream model providers described by their current policies

Do not upload this draft as-is. App Privacy publishing remains a manual App Store Connect gate.
