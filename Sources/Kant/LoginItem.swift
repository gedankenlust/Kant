import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService for "launch at login". This is a system
/// registration tied to the app bundle, not part of config.json — so it is
/// toggled immediately rather than on Save.
///
/// Note: only works for a real, launched .app bundle (not `swift run`).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Failures are reported via the kantError toast.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NotificationCenter.default.post(
                name: .kantError,
                object: "Could not update Login Item: \(error.localizedDescription)"
            )
            return false
        }
    }
}
