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
- Simplified every screen:
  - Vitals opens with one plain sentence about what is outside your typical range, then a Flagged group and everything else. Rows only carry a status word when flagged, the "since last" line and the Notes list are gone, and the Daily health score is replaced by the sentence. Metrics without a reading in 30 days leave the list until the next one; a + button adds any measurement.
  - Time ranges moved from the top of Vitals into each metric's sheet. The sheet lists the latest 10 readings with "Show all", draws the typical band only when it fits the chart, and no longer repeats the range as a sentence.
  - Habits is one view: no Adherence tab (each habit's 30-day rate is in its edit sheet and the overall rate in the header), no per-section counts, streaks from 2 days, and no Category picker.
  - Biomarkers shows "15/16 in range · 1 flagged" without the strip and legend, and past lab reports open from a "lab reports" list instead of tabs (dates now include the year).
  - Chat has one "Set up AI" row that opens Settings, no intro paragraph, and photos attach without asking about the Vault; "Save to Vault" sits on the attachment.
  - Removed the Correlations screen. More is one ruled list. Medications lists Active and Archived without type tabs. Diet and Conditions no longer repeat their titles. Settings shows Apple Health as one row with Connect.
- Renamed the Biomarkers tab to Labs (test-tube icon) and Medications to Meds and Supplements, which no longer shows or asks for a prescription, supplement or OTC type (existing types stay in your data).
- Habit days are now done or not: a tap checks a day and another clears it, and missed days are plain empty boxes instead of slashed ones.
- Conditions and Diet are one Health Profile page under More. Each condition opens its own page showing the lab markers, vitals, meds and supplements, and habits you link to it, side by side with your notes. Common conditions list records that are often tracked with them, and you choose what to link. Meds and habits can be linked to a condition from their own forms. Existing records keep working and start unlinked; a med whose "Taken for" text matches a condition's name exactly is linked once automatically.
- Diet is now "How I eat" on the Health Profile: the current plan, the foods you avoid and your notes. The approved-foods list is gone, the avoided foods can be edited, only one plan is current at a time, and older plans are listed under Past plans. Onboarding now fills in the avoided foods for the diet you pick.
- The AI assistant now sees each condition's notes, diagnosis date and linked records, and what each med is taken for.
- Aura now requires iOS 26.
- Status words, range ticks, flag counts and the newest trend bar use a muted palette: sage for in range, ochre for near a limit, brick for outside a range.
- Added Acknowledgements under Settings with the Phosphor icon license.
- Sample data no longer claims to come from WHOOP: sample vitals are labeled Apple Health, and Sleep Score, Recovery and Strain samples are gone because nothing in the release provides them.
- A Vitals row with one reading this week says "1 reading" instead of leaving the trend blank.
- The assistant now runs on Apple's on-device model by default: no key, and nothing leaves the iPhone. It answers from your records and saves a reading or habit you ask it to log, after you approve. Anthropic and OpenRouter with your own key remain in Settings for PDF and photo lab reports.
- Onboarding is three screens: what Aura is and its privacy promise, Apple Health with units, and the assistant. The feature carousel, diet step and API-key form are gone.
- At the largest text sizes, the Labs summary moves the flag count to its own line and the More list drops its icons so labels fit.
- Chat says "1 message", not "1 messages".
- An empty Labs screen offers to import a lab report instead of sending you to Chat, and empty screens no longer suggest chat requests the on-device assistant can't do.
- A vital's status now matches the number on screen: 6.96 hours, shown as "7.0", is no longer flagged below a 7–9 hour range.
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

- An in-app privacy and support view.
- A privacy manifest covering Aura's UserDefaults access.

### Removed

- CloudKit and iCloud entitlements.
- Native macOS and iPad target support.
- Clinical Health Records, direct FHIR, WHOOP, and Health Auto Export support.
- Automatic AI-generated daily protocol behavior.
