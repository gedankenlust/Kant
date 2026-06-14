import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @State private var config: KantConfig
    @State private var launchAtLogin: Bool
    @State private var selectedTab: Tab = .general
    @State private var saveTask: Task<Void, Never>?

    enum Tab: Hashable {
        case general
        case items
        case diagnostics
        case about
    }

    init(config: KantConfig) {
        _config = State(initialValue: config)
        _launchAtLogin = State(initialValue: LoginItem.isEnabled)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("General", systemImage: "gearshape").tag(Tab.general)
                Label("Items & Profiles", systemImage: "square.grid.2x2").tag(Tab.items)
                Label("Diagnostics", systemImage: "stethoscope").tag(Tab.diagnostics)
                Label("About", systemImage: "info.circle").tag(Tab.about)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView(config: $config, launchAtLogin: $launchAtLogin)
            case .items:
                ItemsSettingsView(config: $config)
            case .diagnostics:
                DiagnosticsSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: config) { _ in scheduleSave() }
        .onChange(of: launchAtLogin) { newValue in
            if !LoginItem.setEnabled(newValue) {
                launchAtLogin = LoginItem.isEnabled
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            AppState.shared.updateConfigAndSave(config)
            NotificationCenter.default.post(name: .kantConfigDidChange, object: nil)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var config: KantConfig
    @Binding var launchAtLogin: Bool
    @State private var usageWasReset = false

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Hotkey") {
                    HotkeyRecorder(hotkey: $config.hotkey)
                        .frame(width: 150, height: 24)
                }
                Toggle("Mouse shortcut (Left + Right click)", isOn: $config.useMouseShortcut)
            }

            Section("Startup") {
                Toggle("Launch Kant at login", isOn: $launchAtLogin)
            }

            Section("Navigation") {
                Toggle("Enable Arrow keys", isOn: $config.useArrowKeys)
                Toggle("Enable Number keys", isOn: $config.useNumberKeys)
                Toggle("Smart ranking (sort by usage)", isOn: $config.useSmartRanking)
            }

            Section("Appearance & Privacy") {
                Picker("Show Kant in", selection: $config.appearanceMode) {
                    Text("Menu Bar").tag("menubar")
                    Text("Dock").tag("dock")
                    Text("Menu Bar + Dock").tag("both")
                }
                Picker("Panel screen", selection: $config.screen) {
                    Text("Follow mouse").tag("mouse")
                    Text("Built-in display").tag("builtin")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        if !screen.isBuiltIn {
                            Text(screen.localizedName).tag("index:\(index)")
                        }
                    }
                }
                Toggle("Fetch favicons from Google", isOn: $config.useFavicons)
            }

            Section("Data") {
                Button(usageWasReset ? "History Cleared" : "Reset Usage History") {
                    UsageTracker.shared.reset()
                    usageWasReset = true
                }
                .disabled(usageWasReset)
                
                Button("Restore Default Configuration") {
                    let d = ConfigLoader.defaultConfig()
                    config = d
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Items & Profiles Settings

struct ItemsSettingsView: View {
    @Binding var config: KantConfig
    @State private var selectedProfileID: String?
    @State private var selectedItemID: String?
    @State private var searchText = ""
    @State private var renamingProfileID: String?

    /// Index of the profile currently being *edited* (the selected chip), with a
    /// safe fallback to the last-used profile. Editing a profile here never
    /// changes which one the launcher opens to — that always follows last use.
    private var editingIndex: Int {
        if let id = selectedProfileID, let idx = config.profiles.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return config.profiles.indices.contains(config.activeProfile) ? config.activeProfile : 0
    }

    private var itemsBinding: Binding<[ConfigItem]> {
        Binding(
            get: {
                guard config.profiles.indices.contains(editingIndex) else { return [] }
                return config.profiles[editingIndex].sections.first?.items ?? []
            },
            set: { newItems in
                guard config.profiles.indices.contains(editingIndex) else { return }
                if config.profiles[editingIndex].sections.isEmpty {
                    config.profiles[editingIndex].sections = [ConfigSection(title: "Items", items: newItems)]
                } else {
                    config.profiles[editingIndex].sections[0].items = newItems
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ProfileChipBar(
                config: $config,
                selectedProfileID: profileSelection,
                renamingProfileID: $renamingProfileID
            )
            Divider()

            HStack(spacing: 0) {
                listColumn
                    .frame(width: 280)
                Divider()
                editorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = config.profiles[safe: config.activeProfile]?.id ?? config.profiles.first?.id
            }
        }
    }

    /// Selecting a different profile resets the item selection so the editor
    /// never shows an item that belongs to another profile.
    private var profileSelection: Binding<String?> {
        Binding(
            get: { selectedProfileID },
            set: { newValue in
                if newValue != selectedProfileID { selectedItemID = nil }
                selectedProfileID = newValue
            }
        )
    }

    // MARK: List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItemID) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    ItemRowPreview(index: index + 1, item: item)
                        .tag(item.id)
                        .contextMenu {
                            if config.profiles.count > 1 {
                                Menu {
                                    ForEach(Array(config.profiles.enumerated()), id: \.element.id) { idx, profile in
                                        if idx != editingIndex {
                                            Button(profile.name.isEmpty ? "Unnamed Profile" : profile.name) {
                                                moveItem(id: item.id, toProfile: idx)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Move to Profile", systemImage: "arrow.right.arrow.left")
                                }
                                Divider()
                            }
                            Button(role: .destructive) { delete(itemID: item.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove(perform: moveItems)
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search items")
            .onDeleteCommand { if let id = selectedItemID { delete(itemID: id) } }

            addBar
        }
    }

    private var addBar: some View {
        VStack(spacing: 8) {
            Menu {
                Button { addItem(type: "url") } label: { Label("URL", systemImage: "link") }
                Button { addAppItem() } label: { Label("Application…", systemImage: "app.badge") }
                Button { addFolderItem() } label: { Label("Folder…", systemImage: "folder") }
                Button { addItem(type: "shortcut") } label: { Label("Shortcut", systemImage: "command") }
            } label: {
                Label("Add item", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(.kantAccent)
            .controlSize(.large)

            Text("Right-click an item to delete it. Kant is optimized for up to 10 items per profile.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }

    // MARK: Editor column

    @ViewBuilder
    private var editorColumn: some View {
        if let id = selectedItemID, let index = itemsBinding.wrappedValue.firstIndex(where: { $0.id == id }) {
            ItemEditor(item: itemsBinding[index])
        } else {
            emptyEditor
        }
    }

    private var emptyEditor: some View {
        let isEmpty = itemsBinding.wrappedValue.isEmpty
        return VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.4))
            Text(isEmpty ? "No items in this profile yet" : "Select an item to edit")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(isEmpty
                 ? "Click “Add item” to create your first launcher tile."
                 : "Or click “Add item” to create a new one.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data

    private var filteredItems: [ConfigItem] {
        let all = itemsBinding.wrappedValue
        if searchText.isEmpty { return all }
        return all.filter { $0.label.localizedCaseInsensitiveContains(searchText) || $0.target.localizedCaseInsensitiveContains(searchText) }
    }

    private func addItem(type: String) {
        let label: String
        let target: String
        switch type {
        case "url": label = "New URL"; target = "https://"
        case "shortcut": label = "New Shortcut"; target = ""
        case "folder": label = "New Folder"; target = ""
        default: label = "New App"; target = ""
        }
        let newItem = ConfigItem(label: label, type: type, target: target)
        itemsBinding.wrappedValue.append(newItem)
        selectedItemID = newItem.id
    }

    /// "Application…" opens the file picker straight away and pre-fills the icon
    /// and label from the chosen app — no blank placeholder step.
    private func addAppItem() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newItem = ConfigItem(
            label: url.deletingPathExtension().lastPathComponent,
            type: "app",
            target: url.path
        )
        itemsBinding.wrappedValue.append(newItem)
        selectedItemID = newItem.id
    }

    /// "Folder…" opens the directory picker straight away and pre-fills the icon
    /// and label from the chosen folder.
    private func addFolderItem() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newItem = ConfigItem(
            label: url.lastPathComponent,
            type: "folder",
            target: url.path
        )
        itemsBinding.wrappedValue.append(newItem)
        selectedItemID = newItem.id
    }

    private func delete(itemID: String) {
        itemsBinding.wrappedValue.removeAll { $0.id == itemID }
        if selectedItemID == itemID { selectedItemID = nil }
    }

    /// Move an item out of the profile being edited and onto another profile.
    private func moveItem(id: String, toProfile targetIndex: Int) {
        guard config.profiles.indices.contains(editingIndex),
              config.profiles.indices.contains(targetIndex),
              targetIndex != editingIndex else { return }

        // Pull the item out of whichever section holds it in the source profile.
        var source = config.profiles[editingIndex]
        var moved: ConfigItem?
        for s in source.sections.indices {
            if let i = source.sections[s].items.firstIndex(where: { $0.id == id }) {
                moved = source.sections[s].items.remove(at: i)
                break
            }
        }
        guard let item = moved else { return }
        config.profiles[editingIndex] = source

        // Append it to the target profile, creating its section if needed.
        if config.profiles[targetIndex].sections.isEmpty {
            config.profiles[targetIndex].sections = [ConfigSection(title: "Items", items: [item])]
        } else {
            config.profiles[targetIndex].sections[0].items.append(item)
        }

        if selectedItemID == id { selectedItemID = nil }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        // Offsets refer to the displayed list; only safe to apply when it equals
        // the full, unfiltered list.
        guard searchText.isEmpty else { return }
        itemsBinding.wrappedValue.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Profile Chip Bar

struct ProfileChipBar: View {
    @Binding var config: KantConfig
    @Binding var selectedProfileID: String?
    @Binding var renamingProfileID: String?

    var body: some View {
        HStack(spacing: 8) {
                ForEach(Array(config.profiles.enumerated()), id: \.element.id) { index, profile in
                    ProfileChip(
                        name: nameBinding(for: index),
                        isSelected: selectedProfileID == profile.id,
                        isRenaming: renamingProfileID == profile.id,
                        canDelete: config.profiles.count > 1,
                        onSelect: { selectedProfileID = profile.id },
                        onBeginRename: {
                            selectedProfileID = profile.id
                            renamingProfileID = profile.id
                        },
                        onEndRename: { renamingProfileID = nil },
                        onDelete: { deleteProfile(at: index) }
                    )
                }

                if config.profiles.count < KantConfig.maxProfiles {
                    Button(action: addProfile) {
                        Label("Profile", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.secondary.opacity(0.4),
                                                  style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add a profile")
                }

                Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { config.profiles.indices.contains(index) ? config.profiles[index].name : "" },
            set: { if config.profiles.indices.contains(index) { config.profiles[index].name = $0 } }
        )
    }

    private func addProfile() {
        guard config.profiles.count < KantConfig.maxProfiles else { return }
        let new = Profile(name: "Profile \(config.profiles.count + 1)")
        config.profiles.append(new)
        selectedProfileID = new.id
        renamingProfileID = new.id
    }

    private func deleteProfile(at index: Int) {
        guard config.profiles.count > 1, config.profiles.indices.contains(index) else { return }
        let removedID = config.profiles[index].id
        config.profiles.remove(at: index)

        // Keep `activeProfile` pointing at the same profile it did before.
        if config.activeProfile >= config.profiles.count {
            config.activeProfile = max(0, config.profiles.count - 1)
        } else if config.activeProfile > index {
            config.activeProfile -= 1
        }

        if selectedProfileID == removedID {
            selectedProfileID = config.profiles[safe: config.activeProfile]?.id
        }
        if renamingProfileID == removedID { renamingProfileID = nil }
    }
}

struct ProfileChip: View {
    @Binding var name: String
    let isSelected: Bool
    let isRenaming: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onBeginRename: () -> Void
    let onEndRename: () -> Void
    let onDelete: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isRenaming {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 84)
                    .focused($fieldFocused)
                    .onSubmit(onEndRename)
                    .onChange(of: fieldFocused) { focused in if !focused { onEndRename() } }
            } else {
                Text(name.isEmpty ? "Unnamed" : name)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isSelected ? Color.kantAccent : Color.secondary.opacity(0.12))
        )
        .contentShape(Capsule())
        .onTapGesture(count: 2) { onBeginRename() }
        .onTapGesture { onSelect() }
        .onChange(of: isRenaming) { renaming in if renaming { fieldFocused = true } }
        .contextMenu {
            Button("Rename") { onBeginRename() }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Text("Delete") }
                .disabled(!canDelete)
        }
        .help("Double-click to rename, right-click to delete.")
    }
}

struct ItemRowPreview: View {
    let index: Int
    let item: ConfigItem
    
    var body: some View {
        HStack {
            Text("\(index).")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
                
            ItemIcon(item: item)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading) {
                Text(item.label.isEmpty ? "Unnamed" : item.label)
                    .font(.body)
                Text(item.type.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ItemEditor: View {
    @Binding var item: ConfigItem

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ItemIcon(item: item)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label.isEmpty ? "Unnamed item" : item.label)
                            .font(.headline)
                            .lineLimit(1)
                        validityBadge
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Item Configuration") {
                TextField("Label", text: $item.label)

                Picker("Type", selection: $item.type) {
                    Text("URL").tag("url")
                    Text("App").tag("app")
                    Text("Folder").tag("folder")
                    Text("Shortcut").tag("shortcut")
                }
                .pickerStyle(.segmented)

                if item.type == "url" {
                    TextField("URL Target", text: $item.target)
                        .help("e.g. https://google.com")
                } else if item.type == "app" {
                    HStack {
                        TextField("App Path", text: $item.target)
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = true
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK, let url = panel.url {
                                item.target = url.path
                                if item.label == "New Item" || item.label == "New App" || item.label.isEmpty {
                                    item.label = url.deletingPathExtension().lastPathComponent
                                }
                            }
                        }
                    }
                } else if item.type == "folder" {
                    HStack {
                        TextField("Folder Path", text: $item.target)
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                            if panel.runModal() == .OK, let url = panel.url {
                                item.target = url.path
                                if item.label == "New Item" || item.label == "New Folder" || item.label.isEmpty {
                                    item.label = url.lastPathComponent
                                }
                            }
                        }
                    }
                } else if item.type == "shortcut" {
                    let shortcuts = AppState.shared.validShortcuts.sorted()
                    if !shortcuts.isEmpty {
                        Picker("Select Installed Shortcut", selection: $item.target) {
                            Text("Select a shortcut...").tag("")
                            ForEach(shortcuts, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                    }
                    TextField("Shortcut Name (Custom)", text: $item.target)
                        .help("If your shortcut is not listed, type it exactly here.")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Validity feedback

    private var isBlank: Bool {
        item.target.isEmpty || item.target == "https://"
    }

    private var isValid: Bool {
        switch item.type {
        case "url":
            guard let url = URL(string: item.target) else { return false }
            return url.scheme != nil && !(url.host ?? "").isEmpty
        case "app":
            return !item.target.isEmpty && FileManager.default.fileExists(atPath: item.target)
        case "folder":
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: item.target, isDirectory: &isDir)
            return !item.target.isEmpty && exists && isDir.boolValue
        case "shortcut":
            let valid = AppState.shared.validShortcuts
            return !item.target.isEmpty && (valid.isEmpty || valid.contains(item.target))
        default:
            return false
        }
    }

    @ViewBuilder
    private var validityBadge: some View {
        if isBlank {
            Label(placeholderHint, systemImage: "pencil.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if isValid {
            Label("Ready to launch", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else {
            Label(invalidHint, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    private var placeholderHint: String {
        switch item.type {
        case "app": return "Choose an application below"
        case "folder": return "Choose a folder below"
        case "shortcut": return "Pick a shortcut below"
        default: return "Enter a URL below"
        }
    }

    private var invalidHint: String {
        switch item.type {
        case "app": return "No app found at this path"
        case "folder": return "No folder found at this path"
        case "shortcut": return "Shortcut “\(item.target)” not found"
        default: return "Not a valid URL"
        }
    }
}

// MARK: - Diagnostics Settings

struct DiagnosticsSettingsView: View {
    @State private var logs: [Log.LogEntry] = Log.inMemoryLogs

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagnostics")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                Text("Accessibility Status:")
                if AXIsProcessTrusted() {
                    Text("Granted").foregroundColor(.green).fontWeight(.medium)
                } else {
                    Text("Denied or Not Requested").foregroundColor(.red).fontWeight(.medium)
                }
            }
            .font(.subheadline)
            
            HStack {
                Text("App Logs")
                    .font(.headline)
                Spacer()
                Button("Copy Logs") {
                    let text = logs.map { "[\($0.timestamp)] \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Clear") {
                    Log.clearInMemoryLogs()
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if logs.isEmpty {
                        Text("No logs available.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(logs) { entry in
                            Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.message)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(entry.isError ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(24)
        .onReceive(NotificationCenter.default.publisher(for: .kantLogAdded)) { _ in
            logs = Log.inMemoryLogs
        }
        .onAppear {
            logs = Log.inMemoryLogs
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    private static let repoURL = URL(string: "https://github.com/gedankenlust/Kant")!

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "dev"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Kant")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("A fast macOS menu-bar launcher for URLs, apps, folders, and Apple Shortcuts.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Link(destination: Self.repoURL) {
                    Label("View on GitHub", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .tint(.kantAccent)

                Button {
                    NSWorkspace.shared.open(Self.repoURL.appendingPathComponent("issues"))
                } label: {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Spacer()

            Text("© 2026 gedankenlust · MIT License")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Helpers

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
