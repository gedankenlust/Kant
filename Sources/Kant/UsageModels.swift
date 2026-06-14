import Foundation

struct UsageLog: Codable {
    var entries: [UsageEntry]

    init(entries: [UsageEntry] = []) {
        self.entries = entries
    }
}

struct UsageEntry: Codable {
    let itemId: String
    let timestamp: Date
    let hour: Int          // 0–23
    let weekday: Int       // 1–7 (Swift: Sunday=1)
    let foregroundApp: String?  // Bundle ID (z.B. "com.apple.Xcode")
    let screen: String     // z.B. "mouse", "builtin", "index:1"
}
