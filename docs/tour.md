# A tour of Aura

What Aura tracks, the health assistant, and the tech stack. The short version is the [README](../README.md).

## What Aura keeps together

The main dashboard brings heart rate, HRV, blood pressure, sleep, steps, weight, SpO2, skin temperature, calories, and other measurements into one timeline. A one-line summary on top says what is outside your typical range, and flagged metrics come first. Each metric opens a chart (7 days to a year), its typical range, and a short explanation.

![Aura vitals dashboard](https://github.com/user-attachments/assets/461e9c5c-3aeb-475f-992c-851c2ba307ef)

Habits, medications, supplements, conditions, diet notes, and lab sessions live beside the measurements they may affect. Biomarkers are grouped by body system, and each past lab report opens from the lab reports list with its own values and notes.

The optional health assistant can read and update vitals, biomarkers, medications, and habits. Attach a lab report as a PDF or photo and it can extract values for review before saving them. You choose Anthropic or OpenRouter and use your own API key.

![Aura health assistant chat](https://github.com/user-attachments/assets/97c3587f-c2d9-4356-8d3c-1284d5e3e762)

https://github.com/user-attachments/assets/d81e0380-41ab-45e5-b22e-92e15c38edad

## Tech stack

- Swift and SwiftUI for iPhone
- SwiftData for local storage
- read-only HealthKit integration
- Anthropic and OpenRouter for optional AI chat
- Keychain storage for provider API keys
