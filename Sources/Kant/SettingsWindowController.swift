import Cocoa
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kant Settings"
        window.center()

        let cfg = AppState.shared.config
        window.contentView = NSHostingView(
            rootView: SettingsView(
                config: cfg
            )
        )

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
