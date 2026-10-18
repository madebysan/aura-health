# Aura Health Design System

Aura is a calm, native iPhone health dashboard. The interface should make dense personal information legible without looking clinical, alarming, or gamified.

The visual direction is **Notebook**: a personal lab notebook. Ink on paper, numbers in SF Mono, hairline rules instead of cards, and one signal color for results that need attention. It was chosen on 2026-10-18 after comparing three directions; the prototypes are in `design/prototypes/`.

## Principles

1. **Personal, not diagnostic.** Show records, trends, and educational context without presenting medical conclusions.
2. **Calm before clever.** Prefer familiar iOS navigation, controls, typography, and motion over novelty.
3. **Details on demand.** Summaries lead; reference ranges, history, explanations, and editing live one level deeper.
4. **Privacy is visible.** AI and data-sharing states must be understandable before a user acts.
5. **Color supports meaning.** Never rely on color alone for health or status communication.

## Platform

- iPhone only for v1.
- Minimum deployment target: iOS 26 (decided 2026-10-18). Liquid Glass, the `Tab` API and Apple's on-device Foundation Models are always available; no `#available` branches.
- Support the smallest and largest current iPhone layouts.
- Remain functional if Apple runs the iPhone build in iPad compatibility mode.
- Use system typography, Dynamic Type, VoiceOver labels, and native interaction patterns.

## Visual language

- Tokens live in `AuraHealth/App/Notebook.swift`. Use them instead of system colors on Aura's own screens.
- Canvas: `Notebook.paper` (warm off-white, near-black in dark mode). Sheets use `Notebook.paperRaised`.
- Text: `Notebook.ink`, `inkSecondary` and `inkTertiary`. All meet WCAG AA on paper in both modes; tertiary is for inactive tabs and placeholders only.
- Structure comes from hairline rules (`.ruled()`) and spacing, not cards, shadows or materials. `cardStyle` remains for secondary screens as a flat raised-paper surface with a hairline.
- System chrome (tab bar, toolbar, sheets) stays native Liquid Glass. The app tint is ink. Do not restyle bars.
- No decorative color. Category colors, colored icon tiles and per-metric chart colors are gone; icons are monochrome ink.

## Status colors

A muted status palette (decided 2026-10-18), used only on status words, range ticks, flag counts and the newest trend bar. Everything else stays ink.

- Sage (`Notebook.inRange`, #2F6B40 / #7FBF8F): in range.
- Ochre (`Notebook.near`, #8F5B10 / #E5B45A): near a limit, or just outside it (within the 10% borderline margin).
- Brick (`Notebook.outOfRange`, #B42318 / #F07A6A): outside a range, or clearly outside a lab reference range.
- Signal (`Notebook.signal`, burnt orange) is no longer a status color: it marks destructive actions and errors.
- All four meet WCAG AA (5:1 or better) on paper and raised paper in both modes. Use the tokens through `RangePosition.color` and `AppColors.biomarkerColor`, never hard-coded.

Every flag needs a word: "near limit", "↑ above range", "↓ below range". Color only adds emphasis. On Vitals, in range is the unmarked default: a row with no status word is in range (decided 2026-10-18, D01). Lab results still say "in range", because a lab report is read marker by marker.

## Icons

- Aura uses [Phosphor](https://phosphoricons.com) Light (MIT) instead of SF Symbols; san chose it on 2026-10-18 over Lucide and Material Symbols Sharp. Its thin, even stroke matches the hairline rules.
- Each icon is a custom symbol named `ph.<phosphor-name>` in `Assets.xcassets/Icons`. Use `Image("ph.heart")` and `Label(title, image: "ph.heart")`; they size with the font like SF Symbols. Do not use `systemName:` or `systemImage:` in new code.
- To add an icon, copy its `-light.svg` from `@phosphor-icons/core` into `assets/icons/phosphor-light/<name>.svg` (without the `-light` suffix), then run `python3 -I scripts/phosphor_symbols.py assets/icons/phosphor-light AuraHealth/Resources/Assets.xcassets/Icons`. The script fills all 27 weight and scale slots with the same outline, because toolbars ask for heavier weights and show nothing if they are missing.
- Apple Health must keep Apple's own Health icon wherever Aura refers to it.

## Typography

- Screen titles use native large-title navigation styling (SF Pro).
- Names, sentences and explanations use SF Pro text styles.
- Numbers, units, dates, status words and labels use SF Mono via `Notebook.mono(_:)`, always with Dynamic Type text styles.
- Small labels ("kickers") are uppercase mono with light tracking: `.kicker()`.
- Primary values are the largest mono text on a row or page; units sit beside or under them in secondary ink.
- Do not lock explanatory health text to a single line.

## Components

- `UnderlineTabs`: mono uppercase tabs with one sliding underline (250 ms). Use for a chart's time range inside a detail sheet. Don't use tabs to switch a whole screen between two views; give the second view its own page.
- `NotebookSectionHeader`: uppercase label, optional trailing count, hairline below.
- `NoteLine`: an insight or warning written as a line ("NOTE … Dismiss"), not a banner.
- `BigNumber`: a large mono value with a quiet suffix ("15/16 in range").
- `StatusWord`: the mono status text next to a value.
- `ReferenceRangeBar` and `MiniRangeBar`: the band is the range, a tick marks the value, labels sit at the band edges. Pass `nil` for a missing limit.
- `BarSparkline`: small bars, latest bar solid. Pass `floor` for bounded scores.
- `NotebookPrimaryButtonStyle` / `NotebookSecondaryButtonStyle`: filled ink and hairline-outlined buttons. Disabled buttons fade to 40%.
- `NotebookCheckbox`: the Habits tick box (filled with a check, empty, or crossed). Use for selections and approved/avoided lists; the row carries the label.
- `NotebookForm`: use instead of `Form` for every sheet and settings screen. It gives paper rows, hairline separators and ink tint, so no screen falls back to the default white iOS form. Title sections with `NotebookFormHeader`.
- `NotebookField`: a form text field whose label stays visible above it, so filled-in edit forms show which field is which. Use instead of a bare `TextField` with a placeholder.
- `EmptyStateView`: explanation plus one primary action.
- `InlineErrorBanner`: recoverable errors without modal interruption.

Prefer these primitives before creating another local variant.

## Navigation

- Main tabs: Vitals, Habits, Labs, Chat, More.
- Keep Settings, Privacy, Health Profile, Meds and Supplements, and Vault under More or a contextual drill-in. More is one ruled list with Settings set apart by space.
- Health Profile holds conditions and "How I eat" (the current diet plan). Each condition opens a page that shows its linked labs, vitals, meds and habits with the same rows those screens use. The page shows records only: it never says a condition is improving or that a med works, and suggestions of what to link are labeled "often tracked with" and are never ticked for the user.
- Vitals is one list: a one-sentence summary, a Flagged group, then everything else. Time ranges live in each metric's sheet. Past lab reports open from "N lab reports" on Labs.
- A habit day is done or not: one tap checks it, another clears it. A missed day is an empty box, the same as an untouched one.
- Use sheets for focused creation/editing and navigation stacks for durable destinations.
- Destructive actions require clear confirmation that names what is removed.

## AI states

- AI is optional and visibly disabled until provider, key, model, and consent are configured.
- Name the active provider and model where the user configures AI.
- Show what data may leave the device before consent.
- Attachments are never sent until the user presses Send.
- Errors preserve the user's draft and avoid exposing provider response bodies or credentials.
- Place the medical disclaimer in onboarding, Chat, Privacy, and biomarker education surfaces.

## Motion

- Use the shared `AppAnimation` curves.
- Motion should explain insertion, expansion, selection, or completion.
- Respect Reduce Motion and avoid perpetual decorative animation.
- Keep common transitions under roughly half a second.

## Accessibility

- Support Larger Text without clipping critical values or actions.
- Provide explicit labels for icon-only controls.
- Use minimum 44-point interactive targets.
- Preserve meaningful reading order in cards and charts.
- Charts need adjacent textual values or summaries.
- Do not claim accessibility support in App Store Connect until the corresponding manual checks pass.

## App Store screenshots

- Use current iPhone Pro Max simulator captures at an accepted App Store size.
- Use clearly labeled sample data; never use personal health information.
- Show 3–5 states in this order: Vitals, Habits, Biomarkers, optional AI Chat, Privacy/Settings.
- Marketing framing may clarify the value, but the real app UI must remain inspectable.
- Screenshot language must match the submitted binary and avoid diagnostic or treatment claims.
