import Cocoa
import SwiftUI
import Darwin

// Allow Ctrl+C in terminal to terminate cleanly
signal(SIGINT) { _ in
    NSApplication.shared.terminate(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: PanelController?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if another Kant is already running (e.g. launched at
        // login plus opened manually), hand off to it and quit — otherwise two
        // menu-bar items and two hotkey handlers fight each other.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if let existing = others.first {
                existing.activate()
                NSApp.terminate(nil)
                return
            }
        }

        setupMainMenu()
        panelController = PanelController()
        panelController?.setupHotkey()
        panelController?.observeConfigChanges()
        applyAppearance()

        // Re-apply menu-bar / Dock presence when the config changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyAppearance),
            name: .kantConfigDidChange,
            object: nil
        )

        // Pre-load shortcut list in background so validation is instant on first panel open.
        Task {
            await AppState.shared.loadShortcutsIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.cleanup()
    }

    /// Clicking the Dock icon (when shown) opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panelController?.window?.isVisible != true {
            panelController?.togglePanel()
        }
        return true
    }

    /// Right-click menu on the Dock icon (Quit is appended by macOS).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: "")
        show.target = self
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(show)
        menu.addItem(settings)
        return menu
    }

    // MARK: - Appearance (menu bar / Dock)

    @objc private func applyAppearance() {
        switch AppState.shared.config.appearanceMode {
        case "dock":
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            removeStatusItem()
        case "both":
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if statusItem == nil { setupStatusItem() }
        default: // "menubar"
            NSApp.setActivationPolicy(.accessory)
            if statusItem == nil { setupStatusItem() }
        }
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu placeholder (required by macOS)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        // Edit menu – enables Cut/Copy/Paste/Select All in all text fields
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let icon = Self.menuBarIcon() {
                button.image = icon
            } else {
                button.title = "K"
            }
            button.toolTip = "Kant"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kant", action: #selector(quitKant), keyEquivalent: "q"))

        self.statusMenu = menu
    }

    /// Kant's "K" mark for the menu bar, as a template image so macOS tints it
    /// for light/dark menu bars. Falls back to a text "K" when the bundled
    /// resource isn't present (e.g. running via `swift run`).
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        let height: CGFloat = 16
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            if let menu = statusMenu {
                statusItem?.menu = menu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil // Reset so next left click works
            }
        } else {
            togglePanel()
        }
    }

    @objc private func togglePanel() {
        panelController?.togglePanel()
    }

    @objc private func openSettings() {
        panelController?.openSettings()
    }

    @objc private func openConfigFolder() {
        let url = ConfigLoader.configDirectoryURL()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func quitKant() {
        NSApplication.shared.terminate(nil)
    }
}
