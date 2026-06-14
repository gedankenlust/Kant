import Foundation
import AppKit

@MainActor
final class UsageTracker {
    static let shared = UsageTracker()

    /// Entries older than this are dropped — they no longer reflect current
    /// behaviour and the ranking weights recency anyway.
    private static let maxAge: TimeInterval = 90 * 24 * 3600
    /// Hard cap as a safety net for extremely heavy users.
    private static let maxEntries = 5000

    private let fileURL: URL
    private var log: UsageLog

    private init() {
        self.fileURL = ConfigLoader.configDirectoryURL().appendingPathComponent("usage.json")
        self.log = Self.load(from: fileURL)
        prune()
    }

    // MARK: - Recording

    func recordUsage(itemId: String, screen: String) {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let foregroundApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let entry = UsageEntry(
            itemId: itemId,
            timestamp: now,
            hour: hour,
            weekday: weekday,
            foregroundApp: foregroundApp,
            screen: screen
        )

        log.entries.append(entry)
        prune()
        save()
    }

    // MARK: - Pruning

    /// Drops entries older than `maxAge` and caps the total count, keeping the
    /// most recent. Cheap and idempotent; safe to call on every record.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        log.entries.removeAll { $0.timestamp < cutoff }
        if log.entries.count > Self.maxEntries {
            log.entries.sort { $0.timestamp < $1.timestamp }
            log.entries.removeFirst(log.entries.count - Self.maxEntries)
        }
    }

    // MARK: - Access

    func usageLog() -> UsageLog {
        log
    }

    /// Wipe all recorded usage (and reset smart-ranking learning).
    func reset() {
        log = UsageLog()
        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(log) {
            try? data.write(to: fileURL)
        }
    }

    private static func load(from url: URL) -> UsageLog {
        let decoder = JSONDecoder()
        // Must match save()'s `.iso8601` encoding, otherwise every decode fails
        // and the usage history silently resets on each launch.
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let log = try? decoder.decode(UsageLog.self, from: data) else {
            return UsageLog()
        }
        return log
    }
}
