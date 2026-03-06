import Foundation
import SwiftData
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// WHOOP API integration via OAuth 2.0
@Observable
@MainActor
final class WhoopService {
    var isConnected = false
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?

    private let clientID: String
    private let clientSecret: String
    private let redirectURI = "aurahealth://whoop/callback"

    private static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    private static let baseAPI = "https://api.prod.whoop.com/developer/v1"

    init() {
        // Load from environment or Keychain
        self.clientID = KeychainService.getValue(for: "whoop-client-id") ?? ""
        self.clientSecret = KeychainService.getValue(for: "whoop-client-secret") ?? ""
        self.isConnected = KeychainService.getValue(for: "whoop-access-token") != nil
        if let lastSync = UserDefaults.standard.object(forKey: "whoop-last-sync") as? Date {
            self.lastSyncDate = lastSync
        }
    }

    // MARK: - OAuth

    var authorizationURL: URL? {
        var components = URLComponents(string: Self.authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read:recovery read:sleep read:workout read:body_measurement"),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]
        return components?.url
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
            isConnected = true
            error = nil
        } catch {
            self.error = "Failed to exchange code: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        KeychainService.deleteValue(for: "whoop-access-token")
        KeychainService.deleteValue(for: "whoop-refresh-token")
        isConnected = false
        lastSyncDate = nil
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

        do {
            try await syncRecovery(token: token, context: context)
            try await syncSleep(token: token, context: context)
            try await syncWorkouts(token: token, context: context)

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "whoop-last-sync")
        } catch {
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    private func syncRecovery(token: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/recovery", token: token)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else { return }

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let recoveryScore = score["recovery_score"] as? Double,
                  let hrvMs = score["hrv_rmssd_milli"] as? Double,
                  let restingHR = score["resting_heart_rate"] as? Double,
                  let createdAt = item["created_at"] as? String,
                  let date = ISO8601DateFormatter().date(from: createdAt) else { continue }

            insertIfNew(context: context, timestamp: date, type: .recovery, value: recoveryScore, source: .whoop)
            insertIfNew(context: context, timestamp: date, type: .hrv, value: hrvMs, source: .whoop)
            insertIfNew(context: context, timestamp: date, type: .heartRate, value: restingHR, source: .whoop)
        }
    }

    private func syncSleep(token: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/activity/sleep", token: token)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else { return }

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let sleepScore = score["sleep_performance_percentage"] as? Double,
                  let createdAt = item["created_at"] as? String,
                  let date = ISO8601DateFormatter().date(from: createdAt) else { continue }

            insertIfNew(context: context, timestamp: date, type: .sleepScore, value: sleepScore, source: .whoop)

            // Sleep duration from start/end
            if let start = item["start"] as? String, let end = item["end"] as? String,
               let startDate = ISO8601DateFormatter().date(from: start),
               let endDate = ISO8601DateFormatter().date(from: end) {
                let hours = endDate.timeIntervalSince(startDate) / 3600
                insertIfNew(context: context, timestamp: date, type: .sleepDuration, value: hours, source: .whoop)
            }

            if let spo2 = score["respiratory_rate"] as? Double {
                insertIfNew(context: context, timestamp: date, type: .spo2, value: spo2, source: .whoop)
            }
            if let skinTemp = score["skin_temp_celsius"] as? Double {
                insertIfNew(context: context, timestamp: date, type: .skinTemp, value: skinTemp, source: .whoop)
            }
        }
    }

    private func syncWorkouts(token: String, context: ModelContext) async throws {
        let data = try await apiRequest(endpoint: "/activity/workout", token: token)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = records["records"] as? [[String: Any]] else { return }

        for item in items {
            guard let score = item["score"] as? [String: Any],
                  let strain = score["strain"] as? Double,
                  let calories = score["kilojoule"] as? Double,
                  let createdAt = item["created_at"] as? String,
                  let date = ISO8601DateFormatter().date(from: createdAt) else { continue }

            insertIfNew(context: context, timestamp: date, type: .strain, value: strain, source: .whoop)
            insertIfNew(context: context, timestamp: date, type: .calories, value: calories / 4.184, source: .whoop) // kJ → kcal
        }
    }

    // MARK: - Helpers

    private func apiRequest(endpoint: String, token: String) async throws -> Data {
        guard let url = URL(string: Self.baseAPI + endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // Token expired — try refresh
            try await refreshToken()
            guard let newToken = KeychainService.getValue(for: "whoop-access-token") else {
                throw URLError(.userAuthenticationRequired)
            }
            var retryRequest = request
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, _) = try await URLSession.shared.data(for: retryRequest)
            return retryData
        }

        return data
    }

    private func refreshToken() async throws {
        guard let refreshToken = KeychainService.getValue(for: "whoop-refresh-token"),
              let url = URL(string: Self.tokenURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(WhoopToken.self, from: data)
        KeychainService.setValue(token.accessToken, for: "whoop-access-token")
        if let refresh = token.refreshToken {
            KeychainService.setValue(refresh, for: "whoop-refresh-token")
        }
    }

    private func insertIfNew(context: ModelContext, timestamp: Date, type: MetricType, value: Double, source: MeasurementSource) {
        // Dedup: check if we already have this metric at this timestamp from this source
        let cal = Calendar.current
        let start = cal.startOfDay(for: timestamp)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let typeRaw = type.rawValue
        let sourceRaw = source.rawValue

        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp < end
                && $0.metricType.rawValue == typeRaw
                && $0.source.rawValue == sourceRaw
            }
        )

        let existing = (try? context.fetchCount(descriptor)) ?? 0
        if existing == 0 {
            context.insert(Measurement(timestamp: timestamp, metricType: type, value: value, source: source))
        }
    }
}

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
