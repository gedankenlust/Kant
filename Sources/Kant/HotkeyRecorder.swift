import SwiftUI
import AppKit
import HotKey

/// A SwiftUI control that records a global hotkey. Click it, press a key combo
/// (with at least one modifier), and it stores a string like "cmd+shift+k" that
/// `PanelController.parseHotkey` understands. Escape cancels.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: String

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { newValue in hotkey = newValue }
        button.hotkeyString = hotkey
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        // Don't clobber the live title while the user is mid-recording.
        if !nsView.isRecording {
            nsView.hotkeyString = hotkey
        }
    }
}

final class RecorderButton: NSButton {
    var onChange: ((String) -> Void)?
    private(set) var isRecording = false
    var hotkeyString: String = "" {
        didSet { updateTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    /// Without this, modifier+key combos (e.g. ⌘W) are consumed as window key
    /// equivalents before they ever reach keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // Escape cancels recording.
        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            window?.makeFirstResponder(nil)
            return
        }

        var modifiers: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.append("cmd") }
        if flags.contains(.control) { modifiers.append("ctrl") }
        if flags.contains(.option) { modifiers.append("opt") }
        if flags.contains(.shift) { modifiers.append("shift") }

        // Require a modifier — a bare global hotkey would hijack normal typing.
        guard !modifiers.isEmpty,
              let key = Key(carbonKeyCode: UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }

        let combo = (modifiers + [key.description.lowercased()]).joined(separator: "+")
        isRecording = false
        hotkeyString = combo
        onChange?(combo)
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        title = isRecording ? "Press shortcut…" : Self.display(hotkeyString)
    }

    /// Render "cmd+shift+k" as "⌘⇧K" for display.
    static func display(_ string: String) -> String {
        guard !string.isEmpty else { return "Click to set" }
        var out = ""
        for part in string.lowercased().split(separator: "+") {
            switch part {
            case "cmd", "command": out += "⌘"
            case "ctrl", "control": out += "⌃"
            case "opt", "option", "alt": out += "⌥"
            case "shift": out += "⇧"
            default: out += part.uppercased()
            }
        }
        return out
    }
}
