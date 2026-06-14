import SwiftUI

/// A thread-safe cache for icons to prevent redundant loads.
@MainActor
private enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    
    static func set(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    static func get(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }
}

/// Displays the best available icon for a config item:
/// - URL → Favicon (fetched from Google's favicon service)
/// - App → App icon from bundle
/// - Shortcut → Shortcuts app icon
struct ItemIcon: View {
    let item: ConfigItem
    @State private var loadedImage: NSImage?

    var body: some View {
        // No fixed frame here — the icon fills whatever size the caller's
        // .frame(...) gives it (52×52 in a tile, 28×20 in a settings row).
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIcon
            }
        }
        .onAppear(perform: loadIcon)
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        switch item.type {
        case "shortcut":
            symbol("bolt.fill", .yellow)
        case "url":
            symbol("globe", .blue)
        case "app":
            symbol("app.fill", .green)
        case "folder":
            symbol("folder.fill", .blue)
        default:
            symbol("questionmark", .secondary)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .padding(2)
    }

    private func loadIcon() {
        switch item.type {
        case "url":
            loadFavicon()
        case "app":
            loadAppIcon()
        case "folder":
            loadFileIcon()
        case "shortcut":
            loadShortcutsAppIcon()
        default:
            break
        }
    }

    /// The Finder icon for a folder (or any file path on disk).
    private func loadFileIcon() {
        guard !item.target.isEmpty else { return }
        let cacheKey = "file-\(item.target)"
        if let cached = IconCache.get(for: cacheKey) {
            self.loadedImage = cached
            return
        }
        guard FileManager.default.fileExists(atPath: item.target) else { return }
        let image = NSWorkspace.shared.icon(forFile: item.target)
        IconCache.set(image, for: cacheKey)
        self.loadedImage = image
    }

    private func loadFavicon() {
        // Respect the privacy toggle: when off, keep the local globe fallback
        // and never contact Google's favicon service.
        guard AppState.shared.config.useFavicons else { return }
        guard let url = URL(string: item.target),
              let host = url.host,
              !host.isEmpty else { return }

        let cacheKey = "favicon-\(host)"
        if let cached = IconCache.get(for: cacheKey) {
            self.loadedImage = cached
            return
        }

        var faviconURL: URL?
        if host.hasSuffix("google.com") {
            let encodedURL = item.target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
            faviconURL = URL(string: "https://www.google.com/s2/favicons?domain_url=\(encodedURL)&sz=128")
        } else {
            faviconURL = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
        }
        
        guard let finalFaviconURL = faviconURL else { return }

        URLSession.shared.dataTask(with: finalFaviconURL) { data, _, _ in
            guard let data = data,
                  let image = NSImage(data: data) else { return }
            
            DispatchQueue.main.async {
                IconCache.set(image, for: cacheKey)
                self.loadedImage = image
            }
        }.resume()
    }

    private func loadAppIcon() {
        let cacheKey = "app-\(item.target)"
        if let cached = IconCache.get(for: cacheKey) {
            self.loadedImage = cached
            return
        }

        let image = NSWorkspace.shared.icon(forFile: item.target)
        IconCache.set(image, for: cacheKey)
        
        DispatchQueue.main.async {
            self.loadedImage = image
        }
    }

    private func loadShortcutsAppIcon() {
        let path = "/System/Applications/Shortcuts.app"
        let cacheKey = "shortcuts-app"
        
        if let cached = IconCache.get(for: cacheKey) {
            self.loadedImage = cached
            return
        }

        guard FileManager.default.fileExists(atPath: path) else { return }
        let image = NSWorkspace.shared.icon(forFile: path)
        IconCache.set(image, for: cacheKey)
        
        DispatchQueue.main.async {
            self.loadedImage = image
        }
    }
}
