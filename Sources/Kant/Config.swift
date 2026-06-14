import Foundation

struct KantConfig: Codable, Equatable {
    var version: Int
    var hotkey: String
    var screen: String
    var useSmartRanking: Bool
    var useArrowKeys: Bool
    var useNumberKeys: Bool
    var useMouseShortcut: Bool
    var useFavicons: Bool
    /// Where Kant shows itself: "menubar" (accessory, no Dock), "dock" (Dock
    /// icon, no menu bar item), or "both".
    var appearanceMode: String
    /// Up to 5 workflow profiles, each with its own items. Always at least one.
    var profiles: [Profile]
    /// Index into `profiles` of the profile the launcher last showed. The panel
    /// reopens to this profile and updates it whenever the user switches, so it
    /// always reflects the most recently used profile (no manual "default").
    var activeProfile: Int

    /// Maximum number of profiles a user can create.
    static let maxProfiles = 5

    /// Sections of the active profile, with safe fallbacks.
    var activeSections: [ConfigSection] {
        guard profiles.indices.contains(activeProfile) else { return profiles.first?.sections ?? [] }
        return profiles[activeProfile].sections
    }

    private enum LegacyKeys: String, CodingKey { case sections }

    init(
        version: Int = 1,
        hotkey: String = "cmd+shift+k",
        screen: String = "mouse",
        useSmartRanking: Bool = false,
        useArrowKeys: Bool = true,
        useNumberKeys: Bool = false,
        useMouseShortcut: Bool = false,
        useFavicons: Bool = true,
        appearanceMode: String = "menubar",
        profiles: [Profile] = [Profile(name: "Default", sections: [])],
        activeProfile: Int = 0
    ) {
        self.version = version
        self.hotkey = hotkey
        self.screen = screen
        self.useSmartRanking = useSmartRanking
        self.useArrowKeys = useArrowKeys
        self.useNumberKeys = useNumberKeys
        self.useMouseShortcut = useMouseShortcut
        self.useFavicons = useFavicons
        self.appearanceMode = appearanceMode
        self.profiles = profiles.isEmpty ? [Profile(name: "Default", sections: [])] : profiles
        self.activeProfile = activeProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? "cmd+shift+k"
        self.screen = try container.decodeIfPresent(String.self, forKey: .screen) ?? "mouse"
        self.useSmartRanking = try container.decodeIfPresent(Bool.self, forKey: .useSmartRanking) ?? false
        self.useArrowKeys = try container.decodeIfPresent(Bool.self, forKey: .useArrowKeys) ?? true
        self.useNumberKeys = try container.decodeIfPresent(Bool.self, forKey: .useNumberKeys) ?? false
        self.useMouseShortcut = try container.decodeIfPresent(Bool.self, forKey: .useMouseShortcut) ?? false
        self.useFavicons = try container.decodeIfPresent(Bool.self, forKey: .useFavicons) ?? true
        self.appearanceMode = try container.decodeIfPresent(String.self, forKey: .appearanceMode) ?? "menubar"

        // Profiles: prefer the new field; otherwise migrate a legacy flat
        // `sections` config into a single "Default" profile.
        if let decoded = try container.decodeIfPresent([Profile].self, forKey: .profiles), !decoded.isEmpty {
            self.profiles = decoded
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let sections = try legacy.decodeIfPresent([ConfigSection].self, forKey: .sections) ?? []
            self.profiles = [Profile(name: "Default", sections: sections)]
        }
        let idx = try container.decodeIfPresent(Int.self, forKey: .activeProfile) ?? 0
        self.activeProfile = profiles.indices.contains(idx) ? idx : 0
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var sections: [ConfigSection]

    init(id: String = UUID().uuidString, name: String, sections: [ConfigSection] = []) {
        self.id = id
        self.name = name
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profile"
        self.sections = try c.decodeIfPresent([ConfigSection].self, forKey: .sections) ?? []
    }

    /// Convenience: all items across this profile's sections.
    var items: [ConfigItem] { sections.flatMap { $0.items } }
}

struct ConfigSection: Codable, Equatable {
    var title: String
    var items: [ConfigItem]
}

struct ConfigItem: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var type: String
    var target: String

    init(id: String = UUID().uuidString, label: String, type: String, target: String) {
        self.id = id
        self.label = label
        self.type = type
        self.target = target
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.label = try container.decode(String.self, forKey: .label)
        self.type = try container.decode(String.self, forKey: .type)
        self.target = try container.decode(String.self, forKey: .target)
    }
}

enum ConfigLoader {
    static func load() -> KantConfig {
        let fileURL = configFileURL()

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let config = defaultConfig()
            if let data = try? JSONEncoder().encode(config) {
                try? data.write(to: fileURL)
            }
            return config
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let config = try JSONDecoder().decode(KantConfig.self, from: data)
            // Write back to migrate old configs (adds missing fields like "screen")
            if let data = try? JSONEncoder().encode(config) {
                try? data.write(to: fileURL)
            }
            return config
        } catch {
            Log.write("Failed to load config: \(String(describing: error))", isError: true)
            return defaultConfig()
        }
    }

    static func save(_ config: KantConfig) {
        let fileURL = configFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL)
        }
    }

    static func configDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Kant") ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Kant")
    }

    static func configFileURL() -> URL {
        configDirectoryURL().appendingPathComponent("config.json")
    }

    /// The factory-default configuration. Internal so Settings can offer
    /// "Restore defaults".
    static func defaultConfig() -> KantConfig {
        KantConfig(
            version: 1,
            hotkey: "cmd+shift+k",
            screen: "mouse",
            useSmartRanking: false,
            useArrowKeys: true,
            useNumberKeys: false,
            useMouseShortcut: false,
            useFavicons: true,
            // Defaults are all URLs so a fresh install works out of the box —
            // no missing Shortcuts showing up as broken (red) tiles. Users add
            // their own apps/shortcuts in Settings.
            profiles: [
                Profile(name: "Default", sections: [
                    ConfigSection(
                        title: "Items",
                        items: [
                            ConfigItem(label: "Google", type: "url", target: "https://www.google.com"),
                            ConfigItem(label: "Gmail", type: "url", target: "https://mail.google.com"),
                            ConfigItem(label: "Calendar", type: "url", target: "https://calendar.google.com"),
                            ConfigItem(label: "YouTube", type: "url", target: "https://www.youtube.com"),
                            ConfigItem(label: "GitHub", type: "url", target: "https://github.com"),
                            ConfigItem(label: "ChatGPT", type: "url", target: "https://chatgpt.com"),
                            ConfigItem(label: "Maps", type: "url", target: "https://maps.google.com"),
                            ConfigItem(label: "Wikipedia", type: "url", target: "https://www.wikipedia.org")
                        ]
                    )
                ])
            ],
            activeProfile: 0
        )
    }
}
