<p><img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon"></p>

<h1>Aura Health</h1>

<p>Your vitals, labs, medications, habits, and health notes in one private dashboard.<br>
Built for people who want to understand their own data, not just collect it.</p>

<p><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-0066cc" alt="SwiftUI">
  <img src="https://img.shields.io/badge/HealthKit-fc3158" alt="HealthKit">
  <img src="https://img.shields.io/badge/Claude%20API-d97757" alt="Claude API">
</p>

<p><a href="#build-from-source">Build Aura from source</a></p>

![Aura app screenshots across iOS and macOS](assets/screenshots.png)

I started Aura after the spreadsheet where I tracked biomarkers, habits, and health notes became harder to understand than the data inside it. The first version was a web app. Moving it to Swift made Apple Health integration and a shared iPhone/Mac experience possible.

Aura is currently distributed as source rather than through the App Store. Your health data stays in the app's local SwiftData store, with optional CloudKit sync between your own devices.

## What Aura keeps together

The main dashboard brings heart rate, HRV, blood pressure, sleep, steps, weight, SpO2, skin temperature, calories, and other measurements into one timeline. Each metric includes a trend, reference range, and a short explanation. Time filters run from the current day through the full history.

![Aura vitals dashboard](https://github.com/user-attachments/assets/461e9c5c-3aeb-475f-992c-851c2ba307ef)

Habits, medications, supplements, conditions, diet notes, and lab sessions live beside the measurements they may affect. Biomarkers are grouped by body system, and previous lab sessions remain available as dated snapshots. Correlation views help compare pairs such as sleep and recovery or HRV and strain.

The built-in health assistant can read and update vitals, biomarkers, medications, and habits. Attach a lab report as a PDF or photo and it can extract values for review before saving them. It uses your own Claude API key.

![Aura health assistant chat](https://github.com/user-attachments/assets/97c3587f-c2d9-4356-8d3c-1284d5e3e762)

https://github.com/user-attachments/assets/d81e0380-41ab-45e5-b22e-92e15c38edad

## Data and privacy

There is no Aura account, server, analytics service, or telemetry. Health data and documents stay on your device. CloudKit can sync the local database between your Apple devices.

When you use the health assistant, Aura sends the message and relevant health context directly to the Anthropic API with the key stored in your Keychain. Local data is not sent anywhere when the assistant is not in use.

Aura can read Apple Health data on iOS, accept manual entries on both platforms, import lab values from chat attachments, and export or restore a JSON backup.

## Build from source

Clone the repository, open `AuraHealth.xcodeproj`, and build the iOS or macOS target in Xcode.

```bash
git clone https://github.com/madebysan/aura-health.git
cd aura-health
open AuraHealth.xcodeproj
```

On first launch, grant Apple Health access on iOS. Add a Claude API key under **Settings → AI** only if you want to use the assistant.

Optional WHOOP OAuth credentials belong in an untracked `Secrets.local.xcconfig` file:

```xcconfig
WHOOP_CLIENT_ID = your-client-id
WHOOP_CLIENT_SECRET = your-client-secret
```

## Known limitations

HealthKit is not available on macOS. Mac users can import data through the app or route exported health data through iCloud Drive.

Lab extraction depends on the image and document quality. Unusual formats or low-resolution photos can produce incomplete results, so every extracted value remains editable before it is saved.

## Tech stack

- Swift, SwiftUI, and one shared iOS/macOS project
- SwiftData and CloudKit for storage and sync
- HealthKit on iOS
- Anthropic's Claude API for the optional assistant
- Keychain storage for the API key

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/aura-health/issues).

## License

[MIT](LICENSE)

Made by [santiagoalonso.com](https://santiagoalonso.com)
