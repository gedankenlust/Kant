import AppKit
import Foundation

@MainActor
enum UrlRunner {
    /// Opens the URL smartly: if the default browser is Safari or a Chromium browser,
    /// it searches for an existing tab with that URL. If found, it focuses the tab.
    /// Otherwise, or if the browser is unsupported, it falls back to NSWorkspace.open.
    static func openUrlSmart(_ url: URL) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        
        let bundleID = Bundle(url: appURL)?.bundleIdentifier?.lowercased() ?? ""
        let appName = appURL.deletingPathExtension().lastPathComponent
        
        // Safari
        if bundleID.contains("com.apple.safari") {
            if !runSafariAppleScript(url: url, appName: appName) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        // Chromium-based (Chrome, Brave, Arc, Edge)
        let chromiumIDs = ["com.google.chrome", "com.brave.browser", "company.thebrowser.browser", "com.microsoft.edgemac"]
        if chromiumIDs.contains(where: { bundleID.contains($0) }) {
            if !runChromiumAppleScript(url: url, appName: appName) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        // Fallback for Firefox and others
        NSWorkspace.shared.open(url)
    }
    
    private static func runSafariAppleScript(url: URL, appName: String) -> Bool {
        let scriptSource = """
        tell application "\(appName)"
            set targetURL to "\(url.absoluteString)"
            set found to false
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        if URL of t starts with targetURL then
                            set current tab of w to t
                            set index of w to 1
                            activate
                            set found to true
                            exit repeat
                        end if
                    end repeat
                end try
                if found is true then exit repeat
            end repeat
            
            if not found then
                open location targetURL
                activate
            end if
        end tell
        """
        return executeScript(scriptSource, appName: appName)
    }
    
    private static func runChromiumAppleScript(url: URL, appName: String) -> Bool {
        let scriptSource = """
        tell application "\(appName)"
            set targetURL to "\(url.absoluteString)"
            set found to false
            repeat with w in windows
                try
                    set tabIndex to 1
                    repeat with t in tabs of w
                        if URL of t starts with targetURL then
                            set active tab index of w to tabIndex
                            set index of w to 1
                            activate
                            set found to true
                            exit repeat
                        end if
                        set tabIndex to tabIndex + 1
                    end repeat
                end try
                if found is true then exit repeat
            end repeat
            
            if not found then
                open location targetURL
                activate
            end if
        end tell
        """
        return executeScript(scriptSource, appName: appName)
    }
    
    private static func executeScript(_ scriptSource: String, appName: String) -> Bool {
        guard let script = NSAppleScript(source: scriptSource) else {
            Log.write("Failed to compile AppleScript for \(appName).", isError: true)
            return false
        }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            let msg = error[NSAppleScript.errorBriefMessage] as? String ?? "Unknown error"
            Log.write("Smart URL focusing failed for \(appName): \(msg)", isError: true)
            return false
        }
        
        return true
    }
}
