import Foundation
import AuthenticationServices
import SwiftData
import os

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "FHIR")

// MARK: - Models

/// A healthcare organization with a FHIR endpoint
struct HealthProvider: Identifiable, Codable, Hashable {
    var id: String              // unique endpoint ID
    var name: String            // display name (e.g. "Kaiser Permanente – Oregon")
    var fhirBaseURL: String     // FHIR R4 base URL
    var network: ProviderNetwork
    var category: ProviderCategory

    enum ProviderNetwork: String, Codable, Hashable {
        case epic = "Epic MyChart"
        case cerner = "Cerner"
        case other = "Other"
    }

    enum ProviderCategory: String, Codable, CaseIterable, Hashable {
        case healthSystem = "Health System"
        case clinic = "Clinic"
        case lab = "Lab"
        case telehealth = "Telehealth"

        var iconName: String {
            switch self {
            case .healthSystem: "building.2.fill"
            case .clinic: "cross.circle.fill"
            case .lab: "flask.fill"
            case .telehealth: "video.fill"
            }
        }
    }

    // Standard Epic OAuth endpoints (same for all Epic organizations)
    var authorizationURL: String {
        switch network {
        case .epic:
            return fhirBaseURL.replacingOccurrences(of: "/api/FHIR/R4/", with: "/oauth2/authorize")
                .replacingOccurrences(of: "/api/FHIR/R4", with: "/oauth2/authorize")
        default:
            return fhirBaseURL + "/oauth2/authorize"
        }
    }

    var tokenURL: String {
        switch network {
        case .epic:
            return fhirBaseURL.replacingOccurrences(of: "/api/FHIR/R4/", with: "/oauth2/token")
                .replacingOccurrences(of: "/api/FHIR/R4", with: "/oauth2/token")
        default:
            return fhirBaseURL + "/oauth2/token"
        }
    }
}

/// Stored connection to a provider
struct FHIRConnection: Codable, Identifiable {
    var id: String { providerID }
    var providerID: String
    var providerName: String
    var fhirBaseURL: String
    var accessToken: String
    var refreshToken: String?
    var tokenExpiry: Date?
    var patientID: String?
    var connectedDate: Date
    var lastSyncDate: Date?
}

// MARK: - Service

/// Manages FHIR provider directory, OAuth connections, and clinical data sync.
@Observable
@MainActor
final class FHIRProviderService {
    var connections: [FHIRConnection] = []
    var providers: [HealthProvider] = []
    var isLoadingDirectory = false
    var isSyncing = false
    var error: String?
    var syncProgress: String?

    // Epic sandbox client ID — works for testing without registration.
    // For production, register at open.epic.com to get your own.
    // This is Epic's public "non-production" client ID for development.
    static let epicClientID = ""  // Set after registering at open.epic.com

    init() {
        loadConnections()
        loadCachedProviders()
    }

    // MARK: - Provider Directory

    /// Fetch Epic's published endpoint directory (thousands of real health systems)
    func fetchProviderDirectory() async {
        isLoadingDirectory = true

        do {
            guard let url = URL(string: "https://open.epic.com/Endpoints/R4") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let bundle = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = bundle["entry"] as? [[String: Any]] else {
                logger.warning("[FHIR] Could not parse endpoint bundle")
                isLoadingDirectory = false
                return
            }

            var parsed: [HealthProvider] = []
            for entry in entries {
                guard let resource = entry["resource"] as? [String: Any],
                      let name = resource["name"] as? String,
                      let fhirURL = resource["address"] as? String,
                      let endpointID = resource["id"] as? String,
                      resource["status"] as? String == "active" else { continue }

                parsed.append(HealthProvider(
                    id: endpointID,
                    name: name,
                    fhirBaseURL: fhirURL,
                    network: .epic,
                    category: .healthSystem
                ))
            }

            // Add curated non-Epic providers
            parsed.append(contentsOf: Self.curatedProviders)

            self.providers = parsed
            cacheProviders(parsed)
            logger.notice("[FHIR] Loaded \(parsed.count) providers from Epic directory")
        } catch {
            logger.error("[FHIR] Failed to fetch directory: \(error.localizedDescription)")
            // Fall back to cached or curated list
            if providers.isEmpty {
                providers = Self.curatedProviders
            }
        }

        isLoadingDirectory = false
    }

    /// Search providers by name (filters the loaded directory)
    func searchProviders(_ query: String) -> [HealthProvider] {
        let source = providers.isEmpty ? Self.curatedProviders : providers
        guard !query.isEmpty else { return Array(source.prefix(50)) }
        let q = query.lowercased()
        return source
            .filter { $0.name.lowercased().contains(q) }
            .prefix(50)
            .map { $0 }
    }

    func isConnected(_ providerID: String) -> Bool {
        connections.contains { $0.providerID == providerID }
    }

    // MARK: - Curated Providers (non-Epic, always available)

    static let curatedProviders: [HealthProvider] = [
        HealthProvider(id: "carbon-health", name: "Carbon Health", fhirBaseURL: "", network: .other, category: .clinic),
        HealthProvider(id: "tia-health", name: "Tia", fhirBaseURL: "", network: .other, category: .clinic),
        HealthProvider(id: "superpower", name: "Superpower", fhirBaseURL: "", network: .other, category: .telehealth),
        HealthProvider(id: "bioreference", name: "BioReference Laboratories", fhirBaseURL: "", network: .other, category: .lab),
        HealthProvider(id: "quest", name: "Quest Diagnostics", fhirBaseURL: "", network: .other, category: .lab),
        HealthProvider(id: "labcorp", name: "Labcorp", fhirBaseURL: "", network: .other, category: .lab),
        HealthProvider(id: "one-medical", name: "One Medical", fhirBaseURL: "", network: .other, category: .clinic),
    ]

    // MARK: - OAuth Connection

    func connect(provider: HealthProvider) async {
        guard !provider.fhirBaseURL.isEmpty else {
            error = "\(provider.name) is not yet available for direct connection. Check if they're available through Apple Health Records instead."
            return
        }

        let clientID = Self.epicClientID
        guard !clientID.isEmpty else {
            error = "Epic MyChart integration requires app registration at open.epic.com. Once registered, set the client ID in the app."
            return
        }

        let redirectURI = "aurahealth://fhir/callback"
        let scope = "patient/Patient.read patient/Observation.read patient/MedicationRequest.read patient/Condition.read patient/AllergyIntolerance.read launch/patient openid fhirUser"
        let state = UUID().uuidString

        var components = URLComponents(string: provider.authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "aud", value: provider.fhirBaseURL),
        ]

        guard let authURL = components.url else {
            error = "Invalid authorization URL"
            return
        }

        logger.notice("[FHIR] Starting OAuth for \(provider.name)")

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "aurahealth") { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: FHIRError.authCancelled)
                    }
                }
                session.prefersEphemeralWebBrowserSession = false

                #if os(iOS)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    session.presentationContextProvider = FHIRAuthPresentationContext(anchor: window)
                }
                #endif

                session.start()
            }

            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                error = "No authorization code received"
                return
            }

            try await exchangeToken(code: code, provider: provider, redirectURI: redirectURI, clientID: clientID)
            logger.notice("[FHIR] Connected to \(provider.name)")

        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                logger.notice("[FHIR] OAuth cancelled by user")
            } else {
                self.error = "Connection failed: \(error.localizedDescription)"
                logger.error("[FHIR] OAuth failed: \(error.localizedDescription)")
            }
        }
    }

    private func exchangeToken(code: String, provider: HealthProvider, redirectURI: String, clientID: String) async throws {
        var request = URLRequest(url: URL(string: provider.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientID)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FHIRError.tokenExchangeFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw FHIRError.invalidTokenResponse
        }

        let connection = FHIRConnection(
            providerID: provider.id,
            providerName: provider.name,
            fhirBaseURL: provider.fhirBaseURL,
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            tokenExpiry: (json["expires_in"] as? Int).map { Date().addingTimeInterval(TimeInterval($0)) },
            patientID: json["patient"] as? String,
            connectedDate: Date()
        )

        if let tokenData = try? JSONEncoder().encode(connection) {
            KeychainService.setData(tokenData, for: "fhir-\(provider.id)")
        }

        connections.removeAll { $0.providerID == provider.id }
        connections.append(connection)
        saveConnections()
    }

    // MARK: - Disconnect

    func disconnect(providerID: String) {
        connections.removeAll { $0.providerID == providerID }
        KeychainService.deleteValue(for: "fhir-\(providerID)")
        saveConnections()
    }

    // MARK: - Sync Clinical Data

    func syncAllProviders(into context: ModelContext) async {
        isSyncing = true
        error = nil

        for connection in connections {
            syncProgress = "Syncing \(connection.providerName)..."
            do {
                try await syncProvider(connection: connection, into: context)
            } catch {
                logger.error("[FHIR] Sync failed for \(connection.providerName): \(error.localizedDescription)")
            }
        }

        try? context.save()
        syncProgress = nil
        isSyncing = false
    }

    private func syncProvider(connection: FHIRConnection, into context: ModelContext) async throws {
        let baseURL = connection.fhirBaseURL
        let token = connection.accessToken

        guard let patientID = connection.patientID else {
            logger.warning("[FHIR] No patient ID for \(connection.providerName)")
            return
        }

        // Fetch lab results
        let labURL = "\(baseURL)Observation?patient=\(patientID)&category=laboratory&_count=200"
        if let labBundle = try? await fetchFHIRBundle(url: labURL, token: token) {
            parseFHIRLabs(labBundle, source: connection.providerName, into: context)
        }

        // Fetch vital signs
        let vitalURL = "\(baseURL)Observation?patient=\(patientID)&category=vital-signs&_count=200"
        if let vitalBundle = try? await fetchFHIRBundle(url: vitalURL, token: token) {
            parseFHIRVitals(vitalBundle, into: context)
        }

        // Fetch medications
        let medURL = "\(baseURL)MedicationRequest?patient=\(patientID)&_count=200"
        if let medBundle = try? await fetchFHIRBundle(url: medURL, token: token) {
            parseFHIRMedications(medBundle, into: context)
        }

        // Fetch conditions
        let condURL = "\(baseURL)Condition?patient=\(patientID)&_count=200"
        if let condBundle = try? await fetchFHIRBundle(url: condURL, token: token) {
            parseFHIRConditions(condBundle, into: context)
        }

        // Update last sync
        if let index = connections.firstIndex(where: { $0.providerID == connection.providerID }) {
            connections[index].lastSyncDate = Date()
            saveConnections()
        }
    }

    // MARK: - FHIR API

    private func fetchFHIRBundle(url: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: url) else { throw FHIRError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw FHIRError.invalidResponse }
        if httpResponse.statusCode == 401 { throw FHIRError.unauthorized }
        guard httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FHIRError.invalidResponse
        }
        return json
    }

    // MARK: - FHIR Parsing

    private func parseFHIRLabs(_ bundle: [String: Any], source: String, into context: ModelContext) {
        guard let entries = bundle["entry"] as? [[String: Any]] else { return }
        for entry in entries {
            guard let resource = entry["resource"] as? [String: Any],
                  resource["resourceType"] as? String == "Observation",
                  let code = resource["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]],
                  let markerName = codings.first?["display"] as? String,
                  let valueQuantity = resource["valueQuantity"] as? [String: Any],
                  let value = valueQuantity["value"] as? Double else { continue }

            let unit = valueQuantity["unit"] as? String ?? ""
            var refMin: Double?
            var refMax: Double?
            if let refRanges = resource["referenceRange"] as? [[String: Any]], let range = refRanges.first {
                refMin = (range["low"] as? [String: Any])?["value"] as? Double
                refMax = (range["high"] as? [String: Any])?["value"] as? Double
            }
            let effectiveDate = parseFHIRDate(resource["effectiveDateTime"] as? String) ?? Date()

            context.insert(Biomarker(
                testDate: effectiveDate, marker: markerName, value: value, unit: unit,
                refMin: refMin, refMax: refMax, lab: source,
                notes: "Imported from \(source)"
            ))
        }
    }

    private func parseFHIRVitals(_ bundle: [String: Any], into context: ModelContext) {
        guard let entries = bundle["entry"] as? [[String: Any]] else { return }
        for entry in entries {
            guard let resource = entry["resource"] as? [String: Any],
                  let code = resource["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]] else { continue }

            let loinc = codings.first(where: { ($0["system"] as? String)?.contains("loinc") == true })?["code"] as? String ?? ""
            guard let metricType = mapLoinc(loinc) else { continue }
            guard let vq = resource["valueQuantity"] as? [String: Any],
                  let value = vq["value"] as? Double else { continue }

            let date = parseFHIRDate(resource["effectiveDateTime"] as? String) ?? Date()
            context.insert(Measurement(timestamp: date, metricType: metricType, value: value, source: .clinicalRecord))
        }
    }

    private func parseFHIRMedications(_ bundle: [String: Any], into context: ModelContext) {
        guard let entries = bundle["entry"] as? [[String: Any]] else { return }
        for entry in entries {
            guard let resource = entry["resource"] as? [String: Any] else { continue }
            var medName: String?
            if let mcc = resource["medicationCodeableConcept"] as? [String: Any] {
                if let codings = mcc["coding"] as? [[String: Any]] { medName = codings.first?["display"] as? String }
                if medName == nil { medName = mcc["text"] as? String }
            }
            guard let name = medName, !name.isEmpty else { continue }

            var dosage = ""
            if let di = resource["dosageInstruction"] as? [[String: Any]], let first = di.first {
                dosage = first["text"] as? String ?? ""
            }
            let startDate = parseFHIRDate(resource["authoredOn"] as? String) ?? Date()
            context.insert(Medication(name: name, dosage: dosage, frequency: .daily, condition: "From clinical records", type: .rx, startDate: startDate))
        }
    }

    private func parseFHIRConditions(_ bundle: [String: Any], into context: ModelContext) {
        guard let entries = bundle["entry"] as? [[String: Any]] else { return }
        for entry in entries {
            guard let resource = entry["resource"] as? [String: Any],
                  let code = resource["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]],
                  let condName = codings.first?["display"] as? String else { continue }

            var status: ConditionStatus = .active
            if let cs = resource["clinicalStatus"] as? [String: Any],
               let sc = (cs["coding"] as? [[String: Any]])?.first?["code"] as? String {
                switch sc {
                case "resolved", "remission", "inactive": status = .resolved
                case "active", "recurrence", "relapse": status = .active
                default: status = .managed
                }
            }
            let onset = parseFHIRDate(resource["onsetDateTime"] as? String)
            context.insert(Condition(name: condName, status: status, diagnosedDate: onset, notes: "From clinical records"))
        }
    }

    // MARK: - Helpers

    private func parseFHIRDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        for fmt in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.dateFormat = fmt
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    private func mapLoinc(_ code: String) -> MetricType? {
        switch code {
        case "85354-9", "8480-6": return .bloodPressure
        case "8867-4": return .heartRate
        case "29463-7", "3141-9": return .weight
        case "8310-5": return .skinTemp
        case "2708-6", "59408-5": return .spo2
        case "80404-7": return .hrv
        default: return nil
        }
    }

    // MARK: - Persistence

    private func saveConnections() {
        let ids = connections.map(\.providerID)
        UserDefaults.standard.set(ids, forKey: "fhir-connected-providers")
        // Re-save tokens
        for connection in connections {
            if let data = try? JSONEncoder().encode(connection) {
                KeychainService.setData(data, for: "fhir-\(connection.providerID)")
            }
        }
    }

    private func loadConnections() {
        guard let ids = UserDefaults.standard.stringArray(forKey: "fhir-connected-providers") else { return }
        connections = ids.compactMap { id in
            guard let data = KeychainService.getData(for: "fhir-\(id)"),
                  let conn = try? JSONDecoder().decode(FHIRConnection.self, from: data) else { return nil }
            return conn
        }
    }

    private func cacheProviders(_ providers: [HealthProvider]) {
        if let data = try? JSONEncoder().encode(providers) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("fhir-providers.json")
            try? data.write(to: cacheURL)
        }
    }

    private func loadCachedProviders() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("fhir-providers.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([HealthProvider].self, from: data) {
            providers = cached
            logger.notice("[FHIR] Loaded \(cached.count) cached providers")
        }
    }
}

// MARK: - Errors

enum FHIRError: LocalizedError {
    case authCancelled, tokenExchangeFailed, invalidTokenResponse
    case invalidURL, invalidResponse, unauthorized

    var errorDescription: String? {
        switch self {
        case .authCancelled: "Authentication was cancelled"
        case .tokenExchangeFailed: "Failed to exchange authorization code"
        case .invalidTokenResponse: "Invalid token response from server"
        case .invalidURL: "Invalid FHIR endpoint URL"
        case .invalidResponse: "Invalid response from FHIR server"
        case .unauthorized: "Session expired — please reconnect"
        }
    }
}

// MARK: - Auth Presentation Context

#if os(iOS)
final class FHIRAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
#endif
