import Foundation
import SwiftData
import os
#if os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "HealthAutoExport")

/// Imports Apple Health data from Health Auto Export iCloud Drive JSON files
@Observable
@MainActor
final class HealthAutoExportService {
    var isEnabled = false
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?
    var syncProgress: SyncProgress?

    struct SyncProgress {
        var imported: Int = 0
        var phase: String = ""
    }

    // Map Health Auto Export metric names → our MetricType
    private static let metricMapping: [String: MetricType] = [
        "step_count": .steps,
        "resting_heart_rate": .heartRate,
        "blood_oxygen_saturation": .spo2,
        "active_energy": .calories,
        "apple_exercise_time": .activeMinutes,
        "heart_rate_variability": .hrv,
        "body_mass": .weight,
        "body_temperature": .skinTemp,
    ]

    private static let bookmarkKey = "hae-folder-bookmark"

    init() {
        if let lastSync = UserDefaults.standard.object(forKey: "hae-last-sync") as? Date {
            self.lastSyncDate = lastSync
        }
        // Check if we have a saved folder bookmark
        isEnabled = resolveBookmark() != nil
        logger.notice("[HAE] Init: enabled=\(self.isEnabled)")
    }

    // MARK: - Folder Access

    /// Let the user pick the Health Auto Export folder via NSOpenPanel
    func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Select Health Auto Export Folder"
        panel.message = "Navigate to iCloud Drive → Health Auto Export → Aura"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        // Start in iCloud Drive
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Save a security-scoped bookmark so we can access it again later
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            isEnabled = true
            error = nil
            logger.notice("[HAE] Folder saved: \(url.path)")
        } catch {
            self.error = "Failed to save folder access: \(error.localizedDescription)"
        }
        #endif
    }

    /// Resolve the saved bookmark to get a URL with sandbox access
    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save the bookmark
            if let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(newData, forKey: Self.bookmarkKey)
            }
        }

        return url
    }

    // MARK: - Sync

    func syncData(into context: ModelContext, days: Int = 7) async {
        guard let folderURL = resolveBookmark() else {
            error = "No folder selected. Tap Connect to choose the Health Auto Export folder."
            return
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            error = "Lost access to folder. Please reconnect."
            isEnabled = false
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        isSyncing = true
        error = nil
        syncProgress = SyncProgress()

        do {
            let files = try findExportFiles(in: folderURL, days: days)
            logger.notice("[HAE] Found \(files.count) export files")

            for file in files {
                syncProgress?.phase = file.lastPathComponent
                try await importFile(file, into: context)
            }

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "hae-last-sync")
        } catch {
            logger.notice("[HAE] Sync error: \(error)")
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        let imported = syncProgress?.imported ?? 0
        syncProgress = nil
        isSyncing = false
        logger.notice("[HAE] Sync complete. Total imported: \(imported)")
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        isEnabled = false
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "hae-last-sync")
        error = nil
    }

    // MARK: - File Discovery

    private func findExportFiles(in folder: URL, days: Int) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        return contents
            .filter { $0.pathExtension == "json" }
            .filter { url in
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return modDate ?? Date.distantPast > cutoff
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Import

    private func importFile(_ url: URL, into context: ModelContext) async throws {
        let data = try Data(contentsOf: url)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let metrics = dataObj["metrics"] as? [[String: Any]] else {
            return
        }

        // Extract date from filename (HealthAutoExport-2026-03-06.json)
        let filename = url.deletingPathExtension().lastPathComponent
        let fileDate = extractDate(from: filename)

        for metric in metrics {
            guard let name = metric["name"] as? String,
                  let samples = metric["data"] as? [[String: Any]] else { continue }

            if name == "sleep_analysis" {
                importSleep(samples, fileDate: fileDate, context: context)
            } else if name == "step_count" {
                importDailySum(samples, type: .steps, fileDate: fileDate, context: context)
            } else if name == "active_energy" {
                importDailySum(samples, type: .calories, fileDate: fileDate, context: context)
            } else if name == "apple_exercise_time" {
                importDailySum(samples, type: .activeMinutes, fileDate: fileDate, context: context)
            } else if let metricType = Self.metricMapping[name] {
                importLatestSample(samples, type: metricType, fileDate: fileDate, context: context)
            }
        }
    }

    /// Import the latest sample per day for a metric (heart rate, SpO2, weight, etc.)
    private func importLatestSample(_ samples: [[String: Any]], type: MetricType, fileDate: Date?, context: ModelContext) {
        guard let lastSample = samples.last,
              let value = lastSample["qty"] as? Double else { return }

        let date = parseDate(lastSample["date"] as? String) ?? fileDate ?? Date()

        if insertIfNew(context: context, timestamp: date, type: type, value: value) {
            syncProgress?.imported += 1
        }
    }

    /// Import cumulative metrics by summing all samples for the day
    private func importDailySum(_ samples: [[String: Any]], type: MetricType, fileDate: Date?, context: ModelContext) {
        let total = samples.reduce(0.0) { sum, sample in
            sum + (sample["qty"] as? Double ?? 0)
        }

        guard total > 0 else { return }

        let date = fileDate ?? parseDate(samples.first?["date"] as? String) ?? Date()

        if insertIfNew(context: context, timestamp: date, type: type, value: total) {
            syncProgress?.imported += 1
        }
    }

    /// Import sleep data (special format with asleep, deep, rem, etc.)
    private func importSleep(_ samples: [[String: Any]], fileDate: Date?, context: ModelContext) {
        guard let sleep = samples.last,
              let totalSleep = sleep["totalSleep"] as? Double else { return }

        // Skip WHOOP-sourced sleep to avoid duplicates
        if let source = sleep["source"] as? String, source.lowercased().contains("whoop") {
            return
        }

        let date = parseDate(sleep["date"] as? String) ?? fileDate ?? Date()

        if insertIfNew(context: context, timestamp: date, type: .sleepDuration, value: totalSleep) {
            syncProgress?.imported += 1
        }
    }

    // MARK: - Helpers

    private func extractDate(from filename: String) -> Date? {
        let parts = filename.replacingOccurrences(of: "HealthAutoExport-", with: "")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: parts)
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: string)
    }

    @discardableResult
    private func insertIfNew(context: ModelContext, timestamp: Date, type: MetricType, value: Double) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: timestamp)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp < end
            }
        )

        let matches = (try? context.fetch(descriptor)) ?? []
        let alreadyExists = matches.contains { $0.metricType == type && $0.source == .appleHealth }

        if !alreadyExists {
            context.insert(Measurement(timestamp: timestamp, metricType: type, value: value, source: .appleHealth))
            return true
        }
        return false
    }
}
