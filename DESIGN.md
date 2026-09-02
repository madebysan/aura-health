# Aura Health Design System

Aura is a calm, native iPhone health dashboard. The interface should make dense personal information legible without looking clinical, alarming, or gamified.

## Principles

1. **Personal, not diagnostic.** Show records, trends, and educational context without presenting medical conclusions.
2. **Calm before clever.** Prefer familiar iOS navigation, controls, typography, and motion over novelty.
3. **Details on demand.** Summaries lead; reference ranges, history, explanations, and editing live one level deeper.
4. **Privacy is visible.** AI and data-sharing states must be understandable before a user acts.
5. **Color supports meaning.** Never rely on color alone for health or status communication.

## Platform

- iPhone only for v1.
- Minimum deployment target: iOS 17.
- Support the smallest and largest current iPhone layouts.
- Remain functional if Apple runs the iPhone build in iPad compatibility mode.
- Use system typography, Dynamic Type, VoiceOver labels, and native interaction patterns.

## Visual language

- Default to system light and dark appearances; do not force a theme.
- Use the system background as the canvas.
- Use regular material or secondary system backgrounds for cards.
- Standard card radius: 14 points.
- Standard card padding: 16 points.
- Borders are subtle, normally `Color.primary.opacity(0.06)`.
- The app accent is the system accent blue. Health categories may use semantic supporting colors.

## Status colors

- Green: in range, complete, or safely configured.
- Orange: borderline, incomplete, or needs attention.
- Red: out of range or destructive action.
- Gray: unavailable, unknown, or neutral.

Every status also needs a label, icon, value, or pattern. A red or green dot alone is insufficient.

## Typography

- Screen titles use native large-title navigation styling.
- Section headings use `.headline` or `.title3.bold()`.
- Primary values are visually dominant and use tabular numbers when comparison matters.
- Supporting explanations use `.subheadline` or `.caption` with secondary foreground style.
- Do not lock explanatory health text to a single line.

## Components

- `cardStyle`: grouped health summaries and detail surfaces.
- `StatusBadge`: short labeled states such as In Range or Access Requested.
- `FilterPill`: time ranges and compact filters.
- `PillSegmentedPicker`: small mutually exclusive choices.
- `EmptyStateView`: explanation plus one primary action.
- `InlineErrorBanner`: recoverable errors without modal interruption.

Prefer these existing primitives before creating another local variant.

## Navigation

- Main tabs: Vitals, Habits, Biomarkers, Chat, More.
- Keep Settings, Privacy, Conditions, Medications, Diet, Correlations, and Vault under More or a contextual drill-in.
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
