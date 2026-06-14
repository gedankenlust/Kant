import Foundation

struct ShortcutRunner {
    /// Run a Shortcut by name via AppleScript. Escapes the name to prevent injection.
    static func runShortcut(named name: String) {
        let escaped = escapeForAppleScript(name)
        let scriptSource = """
        tell application "Shortcuts Events"
            run shortcut "\(escaped)"
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: scriptSource)
            var errorInfo: NSDictionary?
            appleScript?.executeAndReturnError(&errorInfo)

            if let error = errorInfo {
                let msg = "Shortcut '\(name)' failed: \(error[NSAppleScript.errorBriefMessage] as? String ?? "Unknown error")"
                Log.write(msg, isError: true)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .kantError, object: msg)
                }
            }
        }
    }

    /// List all installed shortcut names. Returns empty array on failure.
    static func listShortcuts() -> [String] {
        let scriptSource = """
        tell application "Shortcuts Events"
            set namesList to name of every shortcut
            set AppleScript's text item delimiters to "\n"
            return namesList as string
        end tell
        """

        let appleScript = NSAppleScript(source: scriptSource)
        var errorInfo: NSDictionary?
        guard let result = appleScript?.executeAndReturnError(&errorInfo) else {
            return []
        }

        if let error = errorInfo {
            Log.write("Listing shortcuts failed: \(String(describing: error))", isError: true)
            return []
        }

        guard let text = result.stringValue else {
            return []
        }

        return text.split(separator: "\n").map(String.init)
    }

    // MARK: - AppleScript String Escaping

    /// Escape a string for safe interpolation into an AppleScript double-quoted string.
    /// Handles backslash, double-quote, and control characters.
    /// Internal (not private) so it can be unit-tested.
    static func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
