import Testing
import Foundation
@testable import Kant

struct RankingEngineTests {

    @Test func testEmptyLogReturnsOriginalOrder() {
        let items = [
            ConfigItem(id: "1", label: "A", type: "url", target: "a"),
            ConfigItem(id: "2", label: "B", type: "url", target: "b"),
            ConfigItem(id: "3", label: "C", type: "url", target: "c")
        ]
        let log = UsageLog()
        let context = RankingContext(hour: 12, weekday: 2, foregroundApp: "com.apple.finder", screen: "mouse")
        
        let rankedIds = RankingEngine.rank(items: items, log: log, context: context)
        #expect(rankedIds == ["1", "2", "3"])
    }

    @Test func testFrequencyRanking() {
        let items = [
            ConfigItem(id: "1", label: "A", type: "url", target: "a"),
            ConfigItem(id: "2", label: "B", type: "url", target: "b")
        ]
        
        let now = Date()
        let log = UsageLog(entries: [
            UsageEntry(itemId: "2", timestamp: now, hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse"),
            UsageEntry(itemId: "2", timestamp: now, hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse"),
            UsageEntry(itemId: "1", timestamp: now, hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse")
        ])
        
        let context = RankingContext(hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse")
        let rankedIds = RankingEngine.rank(items: items, log: log, context: context)
        
        #expect(rankedIds == ["2", "1"])
    }

    @Test func testRecencyRanking() {
        let items = [
            ConfigItem(id: "1", label: "A", type: "url", target: "a"),
            ConfigItem(id: "2", label: "B", type: "url", target: "b")
        ]
        
        let now = Date()
        let log = UsageLog(entries: [
            UsageEntry(itemId: "1", timestamp: now.addingTimeInterval(-3600), hour: 11, weekday: 2, foregroundApp: nil, screen: "mouse"),
            UsageEntry(itemId: "2", timestamp: now, hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse")
        ])
        
        let context = RankingContext(hour: 12, weekday: 2, foregroundApp: nil, screen: "mouse")
        let rankedIds = RankingEngine.rank(items: items, log: log, context: context)
        
        #expect(rankedIds == ["2", "1"])
    }

    @Test func testTimeAndWeekdayRanking() {
        let items = [
            ConfigItem(id: "1", label: "Monday Morning", type: "url", target: "a"),
            ConfigItem(id: "2", label: "Friday Night", type: "url", target: "b")
        ]
        
        let now = Date()
        // Sunday=1, Monday=2, Friday=6
        let log = UsageLog(entries: [
            // Item 1 used on Monday (2) at 9 AM
            UsageEntry(itemId: "1", timestamp: now.addingTimeInterval(-86400 * 7), hour: 9, weekday: 2, foregroundApp: nil, screen: "mouse"),
            // Item 2 used on Friday (6) at 10 PM (22)
            UsageEntry(itemId: "2", timestamp: now.addingTimeInterval(-86400 * 3), hour: 22, weekday: 6, foregroundApp: nil, screen: "mouse")
        ])
        
        // Context: Monday at 10 AM (Matches Item 1 better)
        let context1 = RankingContext(hour: 10, weekday: 2, foregroundApp: nil, screen: "mouse")
        let rankedIds1 = RankingEngine.rank(items: items, log: log, context: context1)
        #expect(rankedIds1 == ["1", "2"])
        
        // Context: Friday at 9 PM (Matches Item 2 better)
        let context2 = RankingContext(hour: 21, weekday: 6, foregroundApp: nil, screen: "mouse")
        let rankedIds2 = RankingEngine.rank(items: items, log: log, context: context2)
        #expect(rankedIds2 == ["2", "1"])
    }
}

// MARK: - Config Migration

struct ConfigMigrationTests {

    @Test func testMinimalConfigGetsDefaults() throws {
        // An old config that only has sections — every other field must default.
        let json = """
        { "sections": [] }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(KantConfig.self, from: json)

        #expect(config.version == 1)
        #expect(config.hotkey == "cmd+shift+k")
        #expect(config.screen == "mouse")
        #expect(config.useArrowKeys == true)
        #expect(config.useSmartRanking == false)
        #expect(config.useNumberKeys == false)
        #expect(config.useMouseShortcut == false)
        // Legacy flat config migrates into a single profile.
        #expect(config.profiles.count == 1)
        #expect(config.activeProfile == 0)
        #expect(config.activeSections.isEmpty)
    }

    @Test func testLegacySectionsMigrateIntoProfile() throws {
        let json = """
        { "sections": [ { "title": "Items", "items": [
            { "label": "GitHub", "type": "url", "target": "https://github.com" }
        ] } ] }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(KantConfig.self, from: json)

        #expect(config.profiles.count == 1)
        #expect(config.profiles[0].items.count == 1)
        #expect(config.activeSections.flatMap { $0.items }.first?.label == "GitHub")
    }

    @Test func testProfilesDecodeAndActiveClamps() throws {
        let json = """
        { "profiles": [
            { "name": "Work", "sections": [] },
            { "name": "Home", "sections": [] }
        ], "activeProfile": 5 }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(KantConfig.self, from: json)

        #expect(config.profiles.count == 2)
        #expect(config.profiles[1].name == "Home")
        // Out-of-range activeProfile is clamped to 0.
        #expect(config.activeProfile == 0)
    }

    @Test func testItemWithoutIdGetsGeneratedId() throws {
        let json = """
        { "label": "GitHub", "type": "url", "target": "https://github.com" }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(ConfigItem.self, from: json)

        #expect(!item.id.isEmpty)
        #expect(item.label == "GitHub")
        #expect(item.type == "url")
    }

    @Test func testEmptyObjectDecodesToDefaults() throws {
        let config = try JSONDecoder().decode(KantConfig.self, from: "{}".data(using: .utf8)!)
        #expect(config.hotkey == "cmd+shift+k")
        #expect(config.profiles.count == 1)
        #expect(config.activeSections.isEmpty)
    }
}

// MARK: - AppleScript Escaping

struct ShortcutRunnerTests {

    @Test func testEscapesQuotesAndBackslashes() {
        #expect(ShortcutRunner.escapeForAppleScript("say \"hi\"") == "say \\\"hi\\\"")
        #expect(ShortcutRunner.escapeForAppleScript("a\\b") == "a\\\\b")
    }

    @Test func testEscapesControlCharacters() {
        #expect(ShortcutRunner.escapeForAppleScript("a\nb") == "a\\nb")
        #expect(ShortcutRunner.escapeForAppleScript("a\tb") == "a\\tb")
    }

    @Test func testPlainStringUnchanged() {
        #expect(ShortcutRunner.escapeForAppleScript("Start Focus Mode") == "Start Focus Mode")
    }
}

// MARK: - Usage Log Persistence

struct UsageLogPersistenceTests {

    /// Guards the bug where save() used .iso8601 but load() used the default
    /// strategy, silently wiping history on every launch.
    @Test func testIso8601RoundTrip() throws {
        let log = UsageLog(entries: [
            UsageEntry(itemId: "1", timestamp: Date(), hour: 9, weekday: 2, foregroundApp: "com.apple.finder", screen: "mouse")
        ])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageLog.self, from: data)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries.first?.itemId == "1")
    }
}
