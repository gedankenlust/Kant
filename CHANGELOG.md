# Changelog

All notable changes to Kant are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] — 2026-06-14

First stable release. The settings experience around items and profiles was
reworked from the ground up for clarity.

### Added
- **Folder items**: a fourth item type that opens a folder in Finder. Picking
  "Folder…" opens the directory chooser and auto-fills the icon and label.
- **Move to Profile**: right-click an item to move it to another profile.
- **Guided "Add item" menu**: a labeled button that creates an item of the
  chosen type (URL / Application… / Folder… / Shortcut). "Application…" and
  "Folder…" open the picker immediately and pre-fill icon + label.
- **Live editor feedback**: the item editor shows an icon preview and a status
  line — "Ready to launch", a hint to fill in the target, or a clear warning
  when the target is invalid.

### Changed
- **Unified "Items & Profiles" tab**: the separate "Profiles" and "Items" tabs
  are merged into one. Profiles are managed inline as chips above the item list
  — double-click to rename, right-click to delete, "+ Profile" to add.
- **The launcher always opens to the most recently used profile.** Switching
  profiles in the panel is remembered; there is no manual default to set.
- Deleting an item now uses a right-click context menu and the ⌫ key instead of
  the small +/- list controls.

### Removed
- The standalone "Profiles" settings tab (folded into "Items & Profiles").
- The manual active-profile designation (the star and "Set as Active").

## [0.9.2] — 2026-06-14

### Added
- **About tab** in Settings: app icon, version, tagline, and buttons to view the
  project on GitHub / report an issue, plus license line.

## [0.9.1] — 2026-06-12

### Added
- **Smart URL Tab Focusing**: Kant now intelligently prevents opening duplicate browser tabs. When clicking a URL, it detects your default browser (Safari, Chrome, Brave, Arc, Edge) and uses AppleScript to search your open windows. If the URL is already open, it brings that exact tab to the front.
- **Hybrid Favicons**: Kant now utilizes DuckDuckGo's favicon service for crystal-clear, transparent icons, while falling back to Google's specialized service for specific Google subdomains (like Google Drive and Google Calendar).

## [0.9.0] — 2026-06-12

### Added
- **Settings Redesign**: A modern macOS Settings window utilizing `NavigationSplitView`. Settings are split cleanly into "General", "Profiles", "Items", and "Diagnostics".
- **Real-Time Auto-Save**: Settings changes automatically save in the background (debounced).
- **Master-Detail Items Tab**: Easily edit your Kant items using a proper native editor list. Includes dropdown pickers for your local Apple Shortcuts and an App browser (`NSOpenPanel`).
- **Profile Picker**: Edit items for inactive profiles without needing to switch active profiles.
- **Diagnostics Tab**: Check system accessibility permissions and view in-memory application logs without leaving the app.
- **Proper Build & Deploy**: Added `--install` and `--notarize` flags to `build-app.sh`. Running `--install` gracefully stops Kant and installs the freshly built bundle to `/Applications/Kant.app` for proper macOS permission registration.

### Changed
- Concurrency (`@MainActor`) isolated perfectly in `Log.swift` allowing thread-safe appending of logs without strict synchronous enforcement.

## [0.8.1] — 2026-06-12

### Fixed
- **Tiles are left-aligned with the header/profile bar again** — removed the
  reserved side gutters; the first tile sits flush at the same 32px margin.
- **Scroll-arrow visibility now tracks the real scroll position reliably** by
  observing the underlying NSScrollView's clip bounds (the SwiftUI preference
  approach didn't update during scroll on macOS 13). Arrows float at the edges
  as an overlay, so they don't shift the tiles.

## [0.8.0] — 2026-06-12

### Added
- **Workflow profiles.** Create up to 5 named profiles (Settings → Items →
  profile selector), each with its own item list. A profile bar at the top of
  the panel lets you switch between them with a click; the choice is remembered.
  Old single-list configs migrate automatically into one "Default" profile.

### Changed
- **Scroll arrows now appear only when you can actually scroll that way** — the
  left arrow is hidden at the start, the right arrow hides at the end (tracked
  via live scroll offset).

## [0.7.0] — 2026-06-11

### Added
- **Show Kant in the Dock.** New Settings option (Appearance & Privacy → “Show
  Kant in”): run as a **Menu Bar** app, a **Dock** app, or **both**. Switches the
  activation policy live. Clicking the Dock icon opens the panel, and the Dock
  icon's right-click menu offers Show Panel / Settings. Lets the app icon
  actually appear in use.

## [0.6.7] — 2026-06-11

### Fixed
- **Mouse shortcut works again.** A permission guard added in 0.5.0 blocked the
  global mouse monitor whenever Input Monitoring wasn't "granted" — but global
  *mouse* monitors need no permission (only keyboard ones do), and an ad-hoc
  rebuild resets that state. Removed the guard, the misleading permission
  prompt, and the unused PermissionGuide. Note: requires a real two-button
  mouse (you can't press left + right together on a trackpad / Magic Mouse).

## [0.6.6] — 2026-06-10

### Changed
- **Blank labels stay blank** again: removed the derived-name fallback and the
  Browse… auto-fill. An empty label shows no text — full control.
- **Taller Settings window by default** (760×820) so more items are visible in
  the list before it scrolls.

## [0.6.5] — 2026-06-10

### Changed
- **Both scroll arrows now simply show whenever there are more than 10 items.**
  Dropped the position-based show/hide (it relied on scroll-offset measurement
  that proved unreliable and left the arrows invisible). Clicking an arrow pages
  the row; manual scrolling still works.

## [0.6.4] — 2026-06-09

### Fixed
- Scroll arrows never appeared because the offset was read from a named
  coordinate space that returned nothing (superseded by 0.6.5).

## [0.6.3] — 2026-06-09

### Added
- **Left scroll button** appears when there are items off-screen to the left.

### Changed
- Both scroll buttons now appear/disappear based on the actual scroll position
  (tracked via a preference key) — the right one hides once you reach the end,
  the left one only shows once you've scrolled away from the start.

## [0.6.2] — 2026-06-09

### Changed
- **The overflow “scroll right” chevron is now a real button** — clicking it
  pages the row to the right. It also lives in its own gutter on the right
  instead of overlapping the last tile.

## [0.6.1] — 2026-06-09

### Fixed
- **Whole tile is now clickable**, not just the icon/text — added a content
  shape so the transparent area registers taps too.
- **App tiles with no label now show a name**: falls back to the app/file name
  (or URL host) when the label is blank, and Browse… auto-fills the label from
  the chosen app.

## [0.6.0] — 2026-06-09

Polish pass.

### Added
- **Restore defaults**: a button in Settings → Data resets all items and
  settings to the originals (with confirmation).
- **Smart-ranking hint**: the Items tab notes that manual order is ignored while
  smart ranking is on.
- **Unified logging** (`os.Logger`): failures (config load, Shortcut/app launch)
  go to Console.app under the `com.gedankenlust.kant` subsystem instead of
  stray `print`s.

## [0.5.1] — 2026-06-09

### Fixed
- **First click on a tile sometimes did nothing** — summoning the panel over
  another app made the first click only activate the window. The hosting view
  now accepts the first mouse, so a tile fires on the first press.

## [0.5.0] — 2026-06-09

Reliability pass on the road to 1.0.

### Added
- **Appears over fullscreen apps and on all Spaces** — the panel now sets
  `collectionBehavior`, so the hotkey works even from a fullscreen window.
- **Auto-hide on focus loss**: the panel window can become key again, so
  clicking another app dismisses it.
- **Single-instance**: a second launch (e.g. login item + manual open) hands off
  to the running instance and quits, instead of stacking menu-bar items.
- **Permission guidance**: enabling the mouse shortcut now requests Input
  Monitoring and, if denied, points to the right Privacy pane. The monitor is
  no longer installed without the permission.

### Changed
- **Better default config**: ships universally-working URLs instead of
  placeholder Shortcuts that showed up as broken tiles on a fresh install.

## [0.4.0] — 2026-06-09

### Added
- **Launch at login** toggle in Settings (via `SMAppService`).
- **CI**: GitHub Actions builds and tests on every push / pull request.

### Removed
- **Voice activation** (“Hey Kant”). It relied on `NSSpeechRecognizer`, which
  forces Apple's always-visible speech feedback window and needs microphone
  access — more friction than value. Removed the feature, its setting, the
  config field, and the microphone usage string.

## [0.2.0] — 2026-06-08

First consolidated release after the usability & correctness pass.

### Added
- **Hotkey recorder** in Settings (click-to-record, shown as `⌘⇧K`).
- Settings toggles for **Number Keys** and **Voice Activation** (previously
  only reachable by editing the JSON).
- **Privacy toggle** to disable favicon fetching (keeps URL domains local).
- **Reset usage data** button in Settings.
- `Scripts/build-app.sh` packages a (ad-hoc or Developer-ID) signed `Kant.app`
  with a generated icon.
- `Scripts/make-icon.sh` renders the app icon from code.
- This changelog and a `VERSION` single-source.

### Fixed
- **Usage history was wiped on every launch**: `save()` encoded dates as
  `.iso8601` while `load()` used the default strategy, so every decode failed.
- Ranking is now frozen once per panel open instead of recomputed on every
  access (arrow/number-key indices no longer drift mid-session).
- In-app saves apply **live** (no manual restart).
- The config watcher survives atomic saves (write-temp + rename) from external
  editors.
- Removed a duplicate voice-recognizer setup on launch.

### Changed
- Usage history is pruned to the last 90 days (5000-entry hard cap).
- README rewritten to match reality (macOS 13 / Swift 6, bundle flow,
  permissions, privacy note).

### Notes
- Bundle is **ad-hoc signed** by default; macOS may re-prompt for permissions
  after each rebuild. Set `SIGN_IDENTITY` for a stable Developer ID signature.
- Interactive behaviour (hotkey, voice, mouse shortcut, Shortcuts execution)
  still needs verification on a real machine.
