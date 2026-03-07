import Foundation
import SwiftData
import AuthenticationServices
import os

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "WHOOP")

/// WHOOP API integration via OAuth 2.0
@Observable
@MainActor
final class WhoopService: NSObject {
    var isConnected = false
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?
    var syncProgress: SyncProgress?

    struct SyncProgress {
        var imported: Int = 0
        var phase: String = ""
    }

    // Pre-populated credentials
    private let clientID = "4fcbc49d-71b4-400c-a028-de825fd9ee61"
    private let clientSecret = "4b00a1d93c306b309863f948d98dde9f0669442851fc7936b018fa1cada561b4"
    private let redirectURI = "aurahealth://whoop/callback"
    private let scopes = "offline read:recovery read:sleep read:cycles read:workout read:body_measurement read:profile"

    private static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    private static let baseAPI = "https://api.prod.whoop.com/developer/v2"

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Parse ISO8601 dates with or without fractional seconds
    private func parseDate(_ string: String) -> Date? {
        Self.dateFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    #if os(macOS)
    private var authSession: ASWebAuthenticationSession?
    #endif

    override init() {
        super.init()
        let hasToken = KeychainService.getValue(for: "whoop-access-token") != nil
        self.isConnected = hasToken
        if let lastSync = UserDefaults.standard.object(forKey: "whoop-last-sync") as? Date {
            self.lastSyncDate = lastSync
        }
        logger.notice("[WHOOP] Init: connected=\(hasToken), lastSync=\(String(describing: self.lastSyncDate))")
    }

    // MARK: - OAuth Flow

    func startOAuth() {
        guard var components = URLComponents(string: Self.authURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]

        guard let authURL = components.url else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "aurahealth"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        // User cancelled — not an error
                        return
                    }
                    self.error = "Authentication failed: \(error.localizedDescription)"
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.error = "No authorization code received"
                    return
                }

                await self.exchangeCode(code)
            }
        }

        #if os(macOS)
        session.presentationContextProvider = self
        self.authSession = session
        #endif

        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func exchangeCode(_ code: String) async {
        guard let url = URL(string: Self.tokenURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "redirect_uri=\(redirectURI)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let token = try JSONDecoder().decode(WhoopToken.self, from: data)
            KeychainService.setValue(token.accessToken, for: "whoop-access-token")
            if let refresh = token.refreshToken {
                KeychainService.setValue(refresh, for: "whoop-refresh-token")
            }
            if let expiresIn = token.expiresIn {
                let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
                UserDefaults.standard.set(expiresAt, forKey: "whoop-token-expires")
            }
            isConnected = true
            error = nil
        } catch {
            self.error = "Failed to connect: \(error.localizedDescription)"
        }
    }

    /// Handle URL callback (for cases where ASWebAuthenticationSession doesn't catch it)
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            error = "Invalid callback URL"
            return
        }
        await exchangeCode(code)
    }

    func disconnect() {
        KeychainService.deleteValue(for: "whoop-access-token")
        KeychainService.deleteValue(for: "whoop-refresh-token")
        UserDefaults.standard.removeObject(forKey: "whoop-token-expires")
        isConnected = false
        lastSyncDate = nil
        error = nil
    }

    // MARK: - Data Sync

    func syncData(into context: ModelContext) async {
        guard isConnected else { return }
        guard let token = KeychainService.getValue(for: "whoop-access-token") else {
            error = "No access token found"
            isConnected = false
            return
        }

        isSyncing = true
        error = nil
        syncProgress = SyncProgress()

        // Build start date for queries (last 30 days)
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let startISO = ISO8601DateFormatter().string(from: startDate)

        do {
            logger.notice("[WHOOP] Starting sync, start=\(startISO)")

            syncProgress?.phase = "Recovery"
            try await syncRecovery(token: token, startISO: startISO, context: context)
            let r = self.syncProgress?.imported ?? 0
            logger.notice("[WHOOP] Recovery done, imported: \(r)")

            syncProgress?.phase = "Sleep"
            try await syncSleep(token: token, startISO: startISO, context: context)
            let s = self.syncProgress?.imported ?? 0
            logger.notice("[WHOOP] Sleep done, imported: \(s)")

            syncProgress?.phase = "Workouts"
            try await syncWorkouts(token: token, startISO: startISO, context: context)
            let w = self.syncProgress?.imported ?? 0
            logger.notice("[WHOOP] Workouts done, imported: \(w)")

            syncProgress?.phase = "Body"
            try await syncBody(token: token, context: context)
            let b = self.syncProgress?.imported ?? 0
            logger.notice("[WHOOP] Body done, imported: \(b)")

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "whoop-last-sync")
        } catch {
            logger.notice("[WHOOP] Sync error: \(error)")
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        let imported = syncProgress?.imported ?? 0
        syncProgress = nil
        isSyncing = false
        logger.notice("[WHOOP] Sync complete. Total imported: \(imported)")

        if self.error == nil && imported > 0 {
            // Brief success message
            self.error = nil
        }
    }

    // MARK: - API Endpoints

    private func syncRecovery(token: String, startISO: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/recovery", token: token, queryItems: [
            URLQueryItem(name: "start", value: startISO),
            URLQueryItem(name: "limit", value: "25"),
        ])
        // Debug: write raw response to app container
        if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.prefix(3000).write(to: containerURL.appendingPathComponent("whoop-recovery.json"))
            logger.notice("[WHOOP] Wrote debug to: \(containerURL.path)")
        }
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else {
            logger.notice("[WHOOP] Recovery: failed to parse records array")
            return
        }
        logger.notice("[WHOOP] Recovery: \(items.count) items")

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let createdAt = item["created_at"] as? String,
                  let date = parseDate(createdAt) else { continue }

            if let recoveryScore = score["recovery_score"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .recovery, value: recoveryScore, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
            if let hrvMs = score["hrv_rmssd_milli"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .hrv, value: hrvMs, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
            if let restingHR = score["resting_heart_rate"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .heartRate, value: restingHR, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
            if let spo2 = score["spo2_percentage"] as? Double, spo2 > 0 {
                if insertIfNew(context: context, timestamp: date, type: .spo2, value: spo2, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
            if let skinTemp = score["skin_temp_celsius"] as? Double, skinTemp > 0 {
                if insertIfNew(context: context, timestamp: date, type: .skinTemp, value: skinTemp, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
        }
    }

    private func syncSleep(token: String, startISO: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/activity/sleep", token: token, queryItems: [
            URLQueryItem(name: "start", value: startISO),
            URLQueryItem(name: "limit", value: "25"),
        ])
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else { return }

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let createdAt = item["created_at"] as? String,
                  let date = parseDate(createdAt) else { continue }

            if let sleepScore = score["sleep_performance_percentage"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .sleepScore, value: sleepScore, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }

            // Sleep duration from start/end
            if let start = item["start"] as? String, let end = item["end"] as? String,
               let startDate = parseDate(start),
               let endDate = parseDate(end) {
                let hours = endDate.timeIntervalSince(startDate) / 3600
                if insertIfNew(context: context, timestamp: date, type: .sleepDuration, value: hours, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
        }
    }

    private func syncWorkouts(token: String, startISO: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/activity/workout", token: token, queryItems: [
            URLQueryItem(name: "start", value: startISO),
            URLQueryItem(name: "limit", value: "25"),
        ])
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else { return }

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let createdAt = item["created_at"] as? String,
                  let date = parseDate(createdAt) else { continue }

            if let strain = score["strain"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .strain, value: strain, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
            if let calories = score["kilojoule"] as? Double {
                if insertIfNew(context: context, timestamp: date, type: .calories, value: calories / 4.184, source: .whoop) {
                    syncProgress?.imported += 1
                }
            }
        }
    }

    private func syncBody(token: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/user/measurement/body", token: token)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let weightKg = body["weight_kilogram"] as? Double, weightKg > 0 {
            if insertIfNew(context: context, timestamp: Date(), type: .weight, value: weightKg, source: .whoop) {
                syncProgress?.imported += 1
            }
        }
    }

    // MARK: - API Helpers

    private func apiRequest(endpoint: String, token: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        guard var components = URLComponents(string: Self.baseAPI + endpoint) else {
            throw URLError(.badURL)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshToken()
            guard let newToken = KeychainService.getValue(for: "whoop-access-token") else {
                throw URLError(.userAuthenticationRequired)
            }
            var retryRequest = request
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, _) = try await URLSession.shared.data(for: retryRequest)
            return retryData
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "WHOOP API error (\(httpResponse.statusCode)): \(body)"])
        }

        return data
    }

    private func refreshToken() async throws {
        guard let refreshToken = KeychainService.getValue(for: "whoop-refresh-token"),
              let url = URL(string: Self.tokenURL) else {
            disconnect()
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "scope=offline",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            // Refresh failed — force re-auth
            disconnect()
            throw URLError(.userAuthenticationRequired)
        }

        let token = try JSONDecoder().decode(WhoopToken.self, from: data)
        KeychainService.setValue(token.accessToken, for: "whoop-access-token")
        if let refresh = token.refreshToken {
            KeychainService.setValue(refresh, for: "whoop-refresh-token")
        }
        if let expiresIn = token.expiresIn {
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            UserDefaults.standard.set(expiresAt, forKey: "whoop-token-expires")
        }
    }

    @discardableResult
    private func insertIfNew(context: ModelContext, timestamp: Date, type: MetricType, value: Double, source: MeasurementSource) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: timestamp)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        // Fetch by date range only — SwiftData #Predicate crashes on enum .rawValue comparisons
        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp < end
            }
        )

        let matches = (try? context.fetch(descriptor)) ?? []
        let alreadyExists = matches.contains { $0.metricType == type && $0.source == source }

        if !alreadyExists {
            context.insert(Measurement(timestamp: timestamp, metricType: type, value: value, source: source))
            return true
        }
        return false
    }
}

// MARK: - macOS Presentation Context

#if os(macOS)
extension WhoopService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
#endif

// MARK: - Token Model

private struct WhoopToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
