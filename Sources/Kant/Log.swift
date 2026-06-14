import os
import Foundation

/// Lightweight unified logging. Failures land in Console.app (filter on the
/// "com.gedankenlust.kant" subsystem) for field diagnosis, and are kept in memory
/// for the Settings Diagnostics tab.
enum Log {
    static let app = Logger(subsystem: "com.gedankenlust.kant", category: "app")
    
    /// Thread-safe in-memory buffer of recent logs for the diagnostics UI.
    @MainActor
    private(set) static var inMemoryLogs: [LogEntry] = []
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let isError: Bool
    }
    
    /// Writes to the OS Logger and appends to the in-memory buffer.
    static func write(_ message: String, isError: Bool = false) {
        // OS Log
        if isError {
            app.error("\(message, privacy: .public)")
        } else {
            app.notice("\(message, privacy: .public)")
        }
        
        // In-memory buffer update on Main thread
        Task { @MainActor in
            let entry = LogEntry(message: message, isError: isError)
            inMemoryLogs.append(entry)
            if inMemoryLogs.count > 100 {
                inMemoryLogs.removeFirst()
            }
            NotificationCenter.default.post(name: .kantLogAdded, object: nil)
        }
    }
    
    @MainActor
    static func clearInMemoryLogs() {
        inMemoryLogs.removeAll()
        NotificationCenter.default.post(name: .kantLogAdded, object: nil)
    }
}

extension Notification.Name {
    static let kantLogAdded = Notification.Name("kantLogAdded")
}
