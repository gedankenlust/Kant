import Foundation

/// Watches config.json for external changes and reloads automatically.
@MainActor
final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let fileURL: URL
    private var lastModTime: TimeInterval = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start() {
        stop()

        let path = fileURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            // `.write`/`.extend` cover in-place edits (incl. our own writes).
            // `.delete`/`.rename` catch atomic saves (write-temp + rename) that
            // editors like vim/VS Code perform — those swap the inode, so the
            // old fd goes stale and we must re-attach to keep watching.
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.main
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // Inode swapped — reload, then re-attach to the new file.
                self.handleFileChange()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.start()
                }
            } else {
                self.handleFileChange()
            }
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handleFileChange() {
        // Debounce to avoid double-firing on save
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.reloadIfNeeded()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func reloadIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modTime = attrs[.modificationDate] as? Date else { return }

        let time = modTime.timeIntervalSinceReferenceDate
        // Ignore our own writes by checking if mod time changed significantly
        guard time != lastModTime else { return }
        lastModTime = time

        AppState.shared.reloadConfig()
        NotificationCenter.default.post(name: .kantConfigDidChange, object: nil)
    }

    /// Call this after the app itself writes the config to avoid self-triggering.
    func markOwnWrite() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modTime = attrs[.modificationDate] as? Date else { return }
        lastModTime = modTime.timeIntervalSinceReferenceDate
    }
}

extension Notification.Name {
    static let kantConfigDidChange = Notification.Name("kantConfigDidChange")
    static let kantError = Notification.Name("kantError")
    static let kantNavigateLeft = Notification.Name("kantNavigateLeft")
    static let kantNavigateRight = Notification.Name("kantNavigateRight")
    static let kantExecuteFocused = Notification.Name("kantExecuteFocused")
    static let kantExecuteAtIndex = Notification.Name("kantExecuteAtIndex")
}
