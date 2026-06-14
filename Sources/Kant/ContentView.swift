import SwiftUI
import AppKit

// MARK: - Content View

struct ContentView: View {
    let config: KantConfig
    let validShortcuts: Set<String>
    let onClose: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void

    @State private var focusedIndex: Int = 0
    @State private var pageAnchor: Int = 0
    @State private var scrollX: CGFloat = 0
    @State private var toastMessage: String?
    /// Currently active profile index. Switching re-filters items in place and
    /// persists the choice without rebuilding the panel.
    @State private var activeProfile: Int = 0

    /// Items are ranked exactly once per panel open (or profile switch) and then
    /// frozen. Re-ranking on every access (the old computed property) made the
    /// order depend on `Date()` / frontmost app at each read, so arrow-key and
    /// number-key indices could drift mid-session.
    @State private var allItems: [ConfigItem] = []

    private func baseItems(for profileIndex: Int) -> [ConfigItem] {
        guard config.profiles.indices.contains(profileIndex) else { return [] }
        return config.profiles[profileIndex].sections.flatMap { $0.items }
    }

    private func computeRankedItems() -> [ConfigItem] {
        let baseItems = baseItems(for: activeProfile)
        guard config.useSmartRanking else { return baseItems }

        let now = Date()
        let calendar = Calendar.current
        let context = RankingContext(
            hour: calendar.component(.hour, from: now),
            weekday: calendar.component(.weekday, from: now),
            foregroundApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            screen: config.screen
        )

        let rankedIds = RankingEngine.rank(
            items: baseItems,
            log: UsageTracker.shared.usageLog(),
            context: context
        )

        var itemMap = [String: ConfigItem]()
        for item in baseItems {
            itemMap[item.id] = item
        }

        return rankedIds.compactMap { itemMap[$0] }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.1)

                if config.profiles.count > 1 {
                    profileBar
                    Divider().opacity(0.1)
                }

                content
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )

            if let toast = toastMessage {
                ToastView(message: toast) {
                    toastMessage = nil
                }
            }
        }
        .onAppear {
            activeProfile = config.profiles.indices.contains(config.activeProfile) ? config.activeProfile : 0
            allItems = computeRankedItems()
            focusedIndex = 0
            pageAnchor = 0
            setupNotifications()
        }
        .onDisappear {
            removeNotifications()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Kant")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { onOpenSettings() }) {
                Image(systemName: "gear")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Settings")
            
            Button(action: { onClose() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Close")
            .padding(.leading, 12)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }

    // MARK: - Profile Bar

    private var profileBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(config.profiles.enumerated()), id: \.element.id) { index, profile in
                let isActive = index == activeProfile
                Button(action: { switchProfile(to: index) }) {
                    Text(profile.name.isEmpty ? "Profile \(index + 1)" : profile.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isActive ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isActive ? Color.kantAccent : Color.white.opacity(0.08))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }

    private func switchProfile(to index: Int) {
        guard index != activeProfile, config.profiles.indices.contains(index) else { return }
        activeProfile = index
        allItems = computeRankedItems()
        focusedIndex = 0
        pageAnchor = 0
        // Persist without tearing down the panel.
        AppState.shared.setActiveProfile(index)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if allItems.isEmpty {
            emptyView
        } else {
            itemsView
        }
    }

    private var itemsView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let visibleItems = 10
            // Tiles are flush at 32px, left-aligned with the header / profile bar
            // above. Arrows float at the edges (overlay) so they don't shift the
            // tiles or break that alignment.
            let pad: CGFloat = 32
            let hasOverflow = allItems.count > visibleItems
            let viewportWidth = geo.size.width
            let itemWidth = (viewportWidth - pad * 2 - spacing * CGFloat(visibleItems - 1)) / CGFloat(visibleItems)
            // Fixed tile height (independent of width) so the icon + label
            // always fit without minimumScaleFactor kicking in.
            let tileHeight = min(140, geo.size.height - 12)

            // Real scroll offset comes from the underlying NSScrollView (scrollX:
            // 0 at start, increasing as you scroll right) — reliable, unlike the
            // SwiftUI preference approach which didn't update during scroll.
            let count = CGFloat(allItems.count)
            let contentWidth = count * itemWidth + max(0, count - 1) * spacing + pad * 2
            let maxScroll = max(0, contentWidth - viewportWidth)
            let canScrollLeft = hasOverflow && scrollX > 1
            let canScrollRight = hasOverflow && scrollX < maxScroll - 1

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                            KantTile(
                                index: index,
                                item: item,
                                isValid: isValid(item: item),
                                isFocused: config.useArrowKeys && index == focusedIndex,
                                showNumberBadge: config.useNumberKeys,
                                onExecute: { execute(item: item) }
                            )
                            .frame(width: itemWidth, height: tileHeight)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, pad)
                    .frame(height: geo.size.height)
                    .background(ScrollOffsetReader { scrollX = $0 })
                }
                .onChange(of: focusedIndex) { newIndex in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .overlay(alignment: .leading) {
                    edgeArrow(.left, visible: canScrollLeft) {
                        pageAnchor = max(pageAnchor - visibleItems, 0)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            proxy.scrollTo(pageAnchor, anchor: .leading)
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    edgeArrow(.right, visible: canScrollRight) {
                        pageAnchor = min(pageAnchor + visibleItems, allItems.count - 1)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            proxy.scrollTo(pageAnchor, anchor: .trailing)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private enum ScrollDirection { case left, right }

    @ViewBuilder
    private func edgeArrow(_ direction: ScrollDirection, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(direction == .left ? .leading : .trailing, 4)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.15), value: visible)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("No items found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Validation

    private func isValid(item: ConfigItem) -> Bool {
        if item.type == "url" {
            return URL(string: item.target) != nil
        }
        if item.type == "shortcut" {
            return validShortcuts.isEmpty || validShortcuts.contains(item.target)
        }
        if item.type == "folder" {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: item.target, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
        return true
    }

    // MARK: - Execution

    private func execute(item: ConfigItem) {
        guard isValid(item: item) else {
            showToast("Cannot execute: \(item.label) is invalid")
            return
        }

        // Record usage
        UsageTracker.shared.recordUsage(itemId: item.id, screen: config.screen)

        onClose()

        switch item.type {
        case "shortcut":
            ShortcutRunner.runShortcut(named: item.target)
        case "url":
            if let url = URL(string: item.target) {
                UrlRunner.openUrlSmart(url)
            } else {
                showToast("Invalid URL: \(item.target)")
            }
        case "folder":
            let url = URL(fileURLWithPath: item.target)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.target, isDirectory: &isDir), isDir.boolValue else {
                showToast("Folder not found: \(item.target)")
                return
            }
            NSWorkspace.shared.open(url)
        case "app":
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: item.target) else {
                showToast("App not found: \(item.target)")
                return
            }
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { app, error in
                if let error = error {
                    DispatchQueue.main.async {
                        let msg = "Could not open \(item.label): \(error.localizedDescription)"
                        Log.write(msg, isError: true)
                        NotificationCenter.default.post(
                            name: .kantError,
                            object: msg
                        )
                    }
                }
            }
        default:
            break
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .kantNavigateLeft,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                guard !self.allItems.isEmpty else { return }
                self.focusedIndex = (self.focusedIndex - 1 + self.allItems.count) % self.allItems.count
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kantNavigateRight,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                guard !self.allItems.isEmpty else { return }
                self.focusedIndex = (self.focusedIndex + 1) % self.allItems.count
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kantExecuteFocused,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                guard self.focusedIndex >= 0 && self.focusedIndex < self.allItems.count else { return }
                self.execute(item: self.allItems[self.focusedIndex])
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kantExecuteAtIndex,
            object: nil,
            queue: .main
        ) { [self] notification in
            let rawIndex = notification.object as? Int
            Task { @MainActor in
                guard let rawIndex = rawIndex else { return }
                guard rawIndex >= 0 && rawIndex < self.allItems.count else { return }
                self.focusedIndex = rawIndex
                self.execute(item: self.allItems[rawIndex])
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kantError,
            object: nil,
            queue: .main
        ) { [self] notification in
            let msg = notification.object as? String
            Task { @MainActor in
                if let msg = msg {
                    self.showToast(msg)
                }
            }
        }
    }

    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Tile

struct KantTile: View {
    let index: Int
    let item: ConfigItem
    let isValid: Bool
    let isFocused: Bool
    let showNumberBadge: Bool
    let onExecute: @MainActor () -> Void
    @State private var isHovered = false

    private var numberText: String {
        index == 9 ? "0" : "\(index + 1)"
    }

    var body: some View {
        Button(action: onExecute) {
            ZStack {
                VStack(spacing: 22) {
                    ItemIcon(item: item)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    Text(item.label)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundColor(labelColor)
                        .padding(.horizontal, 4)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showNumberBadge {
                    VStack {
                        HStack {
                            Spacer()
                            Text(numberText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(badgeForeground)
                                .frame(width: 22, height: 22)
                                .background(badgeBackground)
                                .clipShape(Circle())
                                .padding([.top, .trailing], 8)
                        }
                        Spacer()
                    }
                }
            }
            // Make the whole tile clickable, not just the icon/text — without
            // this, SwiftUI only hit-tests the drawn content.
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tileBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(tileBorder, lineWidth: isFocused ? 3 : 0)
        )
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(
            color: tileShadow,
            radius: isFocused ? 12 : (isHovered ? 10 : 0),
            x: 0,
            y: isFocused ? 4 : (isHovered ? 5 : 0)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isHovered)
        .opacity(isValid ? 1.0 : 0.4)
        .disabled(!isValid)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }

    private var badgeForeground: Color {
        if isFocused { return .white }
        return .primary.opacity(0.6)
    }

    private var badgeBackground: Color {
        if isFocused { return Color.kantAccent }
        return Color.white.opacity(0.15)
    }

    private var labelColor: Color {
        if !isValid { return .secondary.opacity(0.5) }
        return .primary
    }

    private var tileBackground: Color {
        if !isValid {
            return Color.white.opacity(0.05)
        }
        if isFocused {
            return Color.kantAccent.opacity(0.15)
        }
        if isHovered {
            return Color.white.opacity(0.12)
        }
        return Color.white.opacity(0.06)
    }

    private var tileBorder: Color {
        if !isValid { return Color.red.opacity(0.25) }
        if isFocused { return Color.kantAccent }
        return Color.clear
    }

    private var tileShadow: Color {
        if !isValid { return .clear }
        if isFocused { return Color.kantAccent.opacity(0.4) }
        if isHovered { return .black.opacity(0.2) }
        return .clear
    }

    private var helpText: String {
        if !isValid {
            if item.type == "shortcut" {
                return "Shortcut '\(item.target)' not found"
            }
            return "Invalid target"
        }
        return item.target
    }
}


// MARK: - Scroll Offset

/// Reports the enclosing NSScrollView's horizontal scroll offset (0 at start,
/// increasing as you scroll right) by observing the clip view's bounds. This is
/// reliable during scrolling, unlike SwiftUI's GeometryReader/preference trick
/// which doesn't update mid-scroll on macOS 13.
struct ScrollOffsetReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onChange = onChange
        DispatchQueue.main.async {
            guard let clip = view.enclosingScrollView?.contentView else { return }
            context.coordinator.start(observing: clip)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// NSObject + selector-based observation avoids capturing a non-Sendable
    /// closure in a @Sendable notification block (Swift 6). Main-actor because
    /// it only ever touches AppKit on the main thread.
    @MainActor
    final class Coordinator: NSObject {
        var onChange: ((CGFloat) -> Void)?
        private weak var clip: NSClipView?

        func start(observing clip: NSClipView) {
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            onChange?(clip.bounds.origin.x)
        }

        @objc private func boundsChanged() {
            onChange?(clip?.bounds.origin.x ?? 0)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
