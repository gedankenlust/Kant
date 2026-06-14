import Foundation

/// Singleton that caches config and shortcut list to avoid disk/AppleScript hits on every panel open.
@MainActor
final class AppState {
    static let shared = AppState()

    private(set) var config: KantConfig
    private(set) var validShortcuts: Set<String> = []
    private(set) var isLoadingShortcuts = false
    private var hasLoadedShortcuts = false
    private let watcher: ConfigWatcher

    private init() {
        self.config = ConfigLoader.load()
        self.watcher = ConfigWatcher(fileURL: ConfigLoader.configFileURL())
        self.watcher.start()
    }

    /// Reload config from disk. Called after external edits (file watcher) or manual refresh.
    func reloadConfig() {
        self.config = ConfigLoader.load()
    }

    /// Update config in-memory, write to disk, and mark the write so the watcher ignores it.
    func updateConfigAndSave(_ newConfig: KantConfig) {
        self.config = newConfig
        ConfigLoader.save(newConfig)
        markConfigWritten()
    }

    /// Persist just the active-profile index. Used by the in-panel profile
    /// switcher — intentionally does NOT post kantConfigDidChange, so the panel
    /// isn't torn down/rebuilt mid-switch.
    func setActiveProfile(_ index: Int) {
        guard config.profiles.indices.contains(index) else { return }
        config.activeProfile = index
        ConfigLoader.save(config)
        markConfigWritten()
    }

    /// Call after the app writes config.json to prevent the watcher from triggering.
    func markConfigWritten() {
        watcher.markOwnWrite()
    }

    /// Load shortcut list once. Idempotent — subsequent calls are no-ops.
    func loadShortcutsIfNeeded() async {
        guard !hasLoadedShortcuts, !isLoadingShortcuts else { return }
        isLoadingShortcuts = true
        defer { isLoadingShortcuts = false }

        let shortcuts = await Task.detached {
            ShortcutRunner.listShortcuts()
        }.value
        validShortcuts = Set(shortcuts)
        hasLoadedShortcuts = true
    }

    /// Force re-validation of shortcuts (e.g. after user creates a new shortcut).
    func invalidateShortcuts() async {
        hasLoadedShortcuts = false
        await loadShortcutsIfNeeded()
    }
}
