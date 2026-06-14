import Cocoa
import SwiftUI
import HotKey

@MainActor
class PanelController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    var hotKey: HotKey?
    var escapeMonitor: Any?
    var mouseMonitor: Any?

    /// Prevents overlapping show/hide calls.
    private var isAnimating = false
    /// Screen ID of the last opened panel, to detect screen changes.
    private var lastScreenID: UInt32?

    // MARK: - Setup

    func setupHotkey() {
        let config = AppState.shared.config
        let (key, modifiers) = parseHotkey(config.hotkey)
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in self?.togglePanel() }
        }
    }

    // MARK: - Toggle

    @objc func togglePanel() {
        guard !isAnimating else { return }

        if let window = window, window.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Show

    func showPanel() {
        guard !isAnimating else { return }
        isAnimating = true

        // 1. Resolve target screen (always follow mouse for reliability)
        let screen = resolveScreen()
        guard let targetScreen = screen else { isAnimating = false; return }

        let screenID = targetScreen.screenID
        let screenChanged = (screenID != lastScreenID)
        lastScreenID = screenID

        let visibleFrame = targetScreen.visibleFrame
        let height: CGFloat = 240
        let panelRect = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - height,
            width: visibleFrame.width,
            height: height
        )

        // 2. Reuse window if possible; only recreate when screen or config changed.
        if window == nil || screenChanged {
            if let old = window {
                old.orderOut(nil)
                self.window = nil
            }
            createWindow(frame: panelRect)
        }

        guard let window = window else { isAnimating = false; return }

        // 3. Position exactly where it should be — no "hidden rect" trick.
        window.setFrame(panelRect, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 4. Fade in — smooth and reliable.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimating = false
            }
        }

        setupKeyboardMonitor()
    }

    // MARK: - Hide

    func hidePanel() {
        guard let window = window else { return }
        guard !isAnimating else { return }
        isAnimating = true

        // Fade out then remove — no frame animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self?.window = nil
                self?.isAnimating = false
            }
        }
        removeKeyboardMonitor()
    }

    // MARK: - Window Factory

    private func createWindow(frame: NSRect) {
        // KantPanelWindow (not a plain NSWindow): borderless windows can't become
        // key by default, which would stop `windowDidResignKey` from firing — so
        // the panel wouldn't auto-hide when you click another app.
        let window = KantPanelWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Appear over fullscreen apps and on every Space — essential for a
        // launcher you trigger from anywhere.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let validShortcuts = AppState.shared.validShortcuts
        let config = AppState.shared.config

        window.contentView = FirstMouseHostingView(
            rootView: ContentView(
                config: config,
                validShortcuts: validShortcuts,
                onClose: { [weak self] in self?.hidePanel() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.hasShadow = true
        window.delegate = self

        window.contentView?.wantsLayer = true
        if let layer = window.contentView?.layer {
            layer.cornerRadius = 20
            layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            layer.masksToBounds = true
        }

        self.window = window
    }

    // MARK: - Screen Resolution

    private func resolveScreen() -> NSScreen? {
        let config = AppState.shared.config
        let mouseScreen = screenWithMouse()

        switch config.screen {
        case "mouse":
            return mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        case "main":
            return NSScreen.main ?? mouseScreen ?? NSScreen.screens.first
        case "primary":
            return NSScreen.screens.first
        case "builtin":
            return NSScreen.screens.first { $0.isBuiltIn } ?? mouseScreen ?? NSScreen.screens.first
        default:
            if config.screen.hasPrefix("index:") {
                let idx = Int(config.screen.dropFirst(6)) ?? 0
                return idx >= 0 && idx < NSScreen.screens.count ? NSScreen.screens[idx] : mouseScreen
            }
            return mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        }
    }

    private func screenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    // MARK: - Hotkey Parsing

    private func parseHotkey(_ string: String) -> (Key, NSEvent.ModifierFlags) {
        let parts = string.lowercased().split(separator: "+")
        var modifiers: NSEvent.ModifierFlags = []
        var key: Key = .k

        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default:
                if let parsed = Key(string: String(part)) {
                    key = parsed
                }
            }
        }
        return (key, modifiers)
    }

    // MARK: - Keyboard Monitor

    private func setupKeyboardMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePanel()
                return nil
            }
            // Arrow Left
            if event.keyCode == 123 {
                if AppState.shared.config.useArrowKeys {
                    NotificationCenter.default.post(name: .kantNavigateLeft, object: nil)
                    return nil
                }
            }
            // Arrow Right
            if event.keyCode == 124 {
                if AppState.shared.config.useArrowKeys {
                    NotificationCenter.default.post(name: .kantNavigateRight, object: nil)
                    return nil
                }
            }
            // Return / Enter
            if event.keyCode == 36 || event.keyCode == 76 {
                if AppState.shared.config.useArrowKeys {
                    NotificationCenter.default.post(name: .kantExecuteFocused, object: nil)
                    return nil
                }
            }
            
            // Number keys 1-9 and 0 (for item 10)
            if AppState.shared.config.useNumberKeys {
                if let char = event.charactersIgnoringModifiers?.first,
                   let digit = char.wholeNumberValue,
                   digit >= 1 && digit <= 9 {
                    NotificationCenter.default.post(
                        name: .kantExecuteAtIndex,
                        object: digit - 1
                    )
                    return nil
                }
                if event.charactersIgnoringModifiers == "0" {
                    NotificationCenter.default.post(
                        name: .kantExecuteAtIndex,
                        object: 9
                    )
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Mouse Monitor

    private func setupMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }

        guard AppState.shared.config.useMouseShortcut else { return }

        // Global monitor for L+R click shortcut. Global *mouse* monitors need no
        // special permission (only keyboard ones do), so we install it directly.
        // 3 = left (1) + right (2) buttons pressed simultaneously.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            // Check if both left and right buttons are pressed
            // 3 = Left (1) + Right (2)
            if NSEvent.pressedMouseButtons == 3 {
                Task { @MainActor in
                    self?.togglePanel()
                }
            }
        }
    }

    // MARK: - Config Change Handling

    func observeConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: .kantConfigDidChange,
            object: nil
        )
        setupMouseMonitor()
    }

    @objc private func configDidChange() {
        guard !isAnimating else { return }
        if let window = window {
            window.orderOut(nil)
            self.window = nil
        }
        lastScreenID = nil
        setupHotkey()
        setupMouseMonitor()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    // MARK: - Settings

    private var settingsWindowController: SettingsWindowController?

    func openSettings() {
        hidePanel()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Cleanup

    func cleanup() {
        removeKeyboardMonitor()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        hotKey = nil
        window?.orderOut(nil)
        window = nil
        settingsWindowController = nil
    }
}

// MARK: - Panel Window

/// Borderless windows return `false` from `canBecomeKey` by default. The panel
/// must be able to become key so that losing focus (clicking another app)
/// reliably triggers `windowDidResignKey` → auto-hide, and so keyboard events
/// are routed to it.
final class KantPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosting view that accepts the first click even when its window wasn't key.
/// Without this, summoning the panel over another app and immediately clicking a
/// tile takes two presses (the first only activates the window).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - NSScreen Extension

extension NSScreen {
    var isBuiltIn: Bool {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(num.uint32Value) != 0
    }

    var screenID: UInt32 {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return num.uint32Value
    }
}
