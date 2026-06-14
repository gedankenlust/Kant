import Foundation

/// Context used by the RankingEngine to compute relevance scores.
struct RankingContext {
    let hour: Int
    let weekday: Int
    let foregroundApp: String?
    let screen: String
}

/// The core logic for dynamically sorting items based on usage history and current context.
enum RankingEngine {

    // MARK: - Weights

    private static let wFreq: Double = 0.15
    private static let wRecency: Double = 0.25
    private static let wTime: Double = 0.20
    private static let wWeekday: Double = 0.10
    private static let wContext: Double = 0.20
    private static let wScreen: Double = 0.10

    // MARK: - Public API

    /// Ranks a list of items based on the provided usage log and current context.
    /// - Parameters:
    ///   - items: The list of items to be ranked.
    ///   - log: The history of recorded usage events.
    ///   - context: The current environment context (time, app, etc.).
    /// - Returns: An array of item IDs sorted from most relevant to least relevant.
    static func rank(items: [ConfigItem], log: UsageLog, context: RankingContext) -> [String] {
        guard !items.isEmpty else { return [] }
        guard !log.entries.isEmpty else { return items.map(\.id) }

        let itemIds = Set(items.map(\.id))
        let relevantEntries = log.entries.filter { itemIds.contains($0.itemId) }

        guard !relevantEntries.isEmpty else { return items.map(\.id) }

        let scores = items.map { item in
            let entries = relevantEntries.filter { $0.itemId == item.id }
            let score = computeScore(entries: entries, context: context)
            return (id: item.id, score: score)
        }

        return scores.sorted { $0.score > $1.score }.map(\.id)
    }

    // MARK: - Scoring

    private static func computeScore(entries: [UsageEntry], context: RankingContext) -> Double {
        guard !entries.isEmpty else { return 0 }

        let freqScore = frequencyScore(count: entries.count)
        let recencyScore = recencyScore(entries: entries)
        let timeScore = timeMatchScore(entries: entries, currentHour: context.hour)
        let weekdayScore = weekdayMatchScore(entries: entries, currentWeekday: context.weekday)
        let contextScore = contextMatchScore(entries: entries, currentApp: context.foregroundApp)
        let screenScore = screenMatchScore(entries: entries, currentScreen: context.screen)

        return wFreq * freqScore
             + wRecency * recencyScore
             + wTime * timeScore
             + wWeekday * weekdayScore
             + wContext * contextScore
             + wScreen * screenScore
    }

    private static func frequencyScore(count: Int) -> Double {
        log(Double(count) + 1.0)
    }

    private static func recencyScore(entries: [UsageEntry]) -> Double {
        guard let last = entries.max(by: { $0.timestamp < $1.timestamp }) else { return 0 }
        let hours = Date().timeIntervalSince(last.timestamp) / 3600.0
        return exp(-hours / 24.0)
    }

    private static func timeMatchScore(entries: [UsageEntry], currentHour: Int) -> Double {
        let matches = entries.filter { abs($0.hour - currentHour) <= 2 }.count
        return Double(matches) / Double(entries.count)
    }

    private static func weekdayMatchScore(entries: [UsageEntry], currentWeekday: Int) -> Double {
        let matches = entries.filter { $0.weekday == currentWeekday }.count
        return Double(matches) / Double(entries.count)
    }

    private static func contextMatchScore(entries: [UsageEntry], currentApp: String?) -> Double {
        guard let currentApp = currentApp else { return 0 }
        let matches = entries.filter { $0.foregroundApp == currentApp }.count
        return Double(matches) / Double(entries.count)
    }

    private static func screenMatchScore(entries: [UsageEntry], currentScreen: String) -> Double {
        let matches = entries.filter { $0.screen == currentScreen }.count
        return Double(matches) / Double(entries.count)
    }
}
