# Aura Health — Session Handoff

## Last session: 2026-03-10

### Done this session

**Clinical Records & FHIR Integration (new feature)**
- Added Apple Health Records (ClinicalHealthRecords) support — reads FHIR R4 clinical data (lab results, medications, conditions, vital signs) from providers connected in the Health app
- Added `health-records` entitlement and `NSHealthClinicalHealthRecordsShareUsageDescription` to Info.plist
- Created `ClinicalRecordService.swift` — full FHIR R4 parser for HKClinicalRecord (Observation → Biomarker, MedicationRequest → Medication, Condition → Condition, vital signs → Measurement)
- Created `FHIRProviderService.swift` — dynamic provider directory that fetches Epic's published endpoint list (~3,000+ US health systems), caches locally, supports search. Full SMART on FHIR OAuth flow via ASWebAuthenticationSession. Parses FHIR bundles for labs, vitals, meds, conditions
- Created `ClinicConnectionView.swift` — Settings > Connect Clinic UI with Apple Health Records section + searchable provider directory (search by hospital/clinic name)
- Added `clinicalRecord` to `MeasurementSource` enum
- Added `setData`/`getData` methods to `KeychainService` for storing Codable FHIR connection tokens
- Added curated non-Epic providers: Carbon Health, Tia, Superpower, BioReference, Quest, Labcorp, One Medical (show "Coming Soon" — no public FHIR endpoints)
- Registered both `ClinicalRecordService` and `FHIRProviderService` as environment objects in `AuraHealthApp.swift`
- Added scheme definition to `project.yml` (was missing after xcodegen regeneration)

**Particle Health Research**
- Researched Particle Health as a potential health data aggregator vendor
- Key finding: Particle connects to Carequality, CommonWell, eHealth Exchange (national HIE networks not accessible to individual developers) — covers ~90% of US EHRs via single API
- Conclusion: Our FHIR approach covers Epic (3,000+ systems). Particle would fill gaps for non-FHIR providers but is a paid B2B service. Evaluate later when users need broader coverage

### Current state
- Build: passing (iOS Debug config)
- App installed on Santiago's iPhone (Debug build with "Load Sample Data" visible in Developer section)
- Bundle ID: `com.santiagoalonso.aurahealth`
- No GitHub repo — local only
- **TestFlight:** Build 2 waiting for Beta App Review (submitted 2026-03-09)
- **FHIR OAuth:** Infrastructure built but not testable yet — needs Epic client ID from open.epic.com registration
- **Apple Health Records:** Ready to use but san has no clinical records connected in Health app

### Next steps
- [ ] Register at open.epic.com for Epic client ID → set in `FHIRProviderService.epicClientID` → test full OAuth flow
- [ ] Wait for Beta App Review approval (build 2)
- [ ] Register WHOOP developer app at developer.whoop.com, configure redirect URI, re-enable OAuth
- [ ] Visual QA pass (`/visual-qa-swift`) across all screens
- [ ] UI polish pass (`/swift-ui-polish`) for animations and micro-interactions
- [ ] Evaluate Particle Health integration for broader provider coverage
- [ ] Verify weight + other sparse metrics loading after Apple Health sync

### Decisions & context
- **Apple Health Records vs direct FHIR:** Both approaches implemented. Apple Health Records is the easiest path (Apple handles provider auth), direct FHIR gives in-app provider search experience
- **Particle Health:** Decided not to integrate now. Unique value is access to national HIE networks (Carequality, CommonWell) which are closed to individual developers. Worth evaluating when user base grows
- **Provider directory:** Using Epic's published R4 endpoint bundle (fetched at runtime, cached locally). Curated providers (Carbon Health, Tia, etc.) included as static entries with empty FHIR URLs until their endpoints are confirmed
- **Sample data button:** Was hidden because previous builds used Release config. Debug builds show it in Settings > Developer. User confirmed this is what they wanted

### Key files modified/created
- `AuraHealth.entitlements` — added `health-records` to HealthKit access
- `Info.plist` — added `NSHealthClinicalHealthRecordsShareUsageDescription`
- `Enums.swift` — added `clinicalRecord` to `MeasurementSource`
- `KeychainService.swift` — added `setData`/`getData` for raw Data storage
- `AuraHealthApp.swift` — registered ClinicalRecordService + FHIRProviderService environments
- `SettingsView.swift` — added "Connect Clinic" navigation link in Integrations
- `project.yml` — added scheme definition
- **New:** `ClinicalRecordService.swift` — Apple Health Records FHIR parser
- **New:** `FHIRProviderService.swift` — FHIR provider directory + OAuth + data sync
- **New:** `ClinicConnectionView.swift` — Connect Clinic UI
