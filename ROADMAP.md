# Bundle — Roadmap

## Architecture overview
9 files, one job each:

| File | Responsibility |
|---|---|
| `AppDelegate` | App entry point, wires all components together |
| `HotkeyManager` | Registers and fires `⌘⌥B` global hotkey |
| `BundleManager` | Single source of truth — owns all bundle state, handles create/delete/save/load |
| `BundlePanelController` | One NSPanel per bundle, hosts SwiftUI content inside |
| `BundleGridView` | SwiftUI grid of cells for a given bundle |
| `CellView` | Individual cell — empty or occupied states |
| `MenuBarView` | SwiftUI popover content for the menu bar icon |
| `BundleState` | Codable data model — name, grid size, cell array, screen position |
| `CellState` | Codable data model — content URL, type (file/folder/image/text), display name |

State management via `@Observable` macro. Persistence via `Codable` structs encoded to JSON.

---

## v0.1 — Foundation
**Goal:** prove the overlay concept. App exists, hotkey fires, panel appears.

- macOS app with no dock icon (`LSUIElement = true` in Info.plist)
- Menu bar icon appears (no popover yet, just the icon)
- `⌘⌥B` global hotkey registered via `HotkeyManager`
- One hardcoded `BundlePanelController` created on launch
- Panel is a floating `NSPanel` — frosted glass material, rounded corners, correct visual aesthetic from day one
- Hardcoded 1x3 grid of empty cells renders inside the panel
- Hotkey shows and hides the panel

**Files introduced:** `AppDelegate`, `HotkeyManager`, `BundlePanelController`, `BundleGridView`, `CellView`

**Done when:** app lives in menu bar, `⌘⌥B` toggles a frosted glass panel with empty circles.

---

## v0.2 — Bundle creation
**Goal:** user can create real bundles from the menu bar.

- Menu bar icon is clickable, opens a translucent SwiftUI popover
- Popover home screen:
  - `+ Add new bundle`
  - Show / Hide (mirrors `⌘⌥B`)
  - Quit
- Tapping `+ Add new bundle` pushes to creation page via `NavigationStack`
- Creation page has:
  - Text field for custom bundle name
  - Table Grid picker — tap to select dimensions (1x1 up to 5x5)
  - Create button
- Hitting Create:
  - `BundleManager` creates a new `BundleState`
  - A new `BundlePanelController` is instantiated and panel appears on screen
  - Popover closes
- Multiple bundles can exist simultaneously
- Hardcoded panel from v0.1 is removed

**Files introduced:** `MenuBarView`, `BundleManager`, `BundleState`

**Done when:** user can create multiple named bundles with different grid sizes from the menu bar.

---

## v0.3 — Bundle positioning & settings
**Goal:** bundles are movable and configurable.

- `:::` handle renders at the top of each bundle panel
- **Hold + drag** on handle moves the panel anywhere on screen
- Position saves to `UserDefaults` per bundle UUID on drag end
- Position restores on next launch
- **Click** on handle opens a settings popover:
  - Rename — editable text field, updates panel header live
  - Change size — re-opens Table Grid picker, resizes the cell grid
  - Delete — removes the panel from screen and deletes its `BundleState`
- `⌘⌥B` correctly shows/hides ALL panels simultaneously

**Files modified:** `BundlePanelController`, `BundleGridView`, `BundleManager`, `BundleState`

**Done when:** bundles are draggable, position persists, settings popover works for all three actions.

---

## v0.4 — Cell interaction & storage
**Goal:** cells accept content and files are stored safely on disk.

These two are built together — doing interaction without storage would mean throwing code away.

### Cell interaction
- One-click selects a cell — blue ring appears, all others deselect
- Clicking empty space or another cell deselects
- `⌘V` on a selected empty cell pastes clipboard content into it
- Drag any file, folder, or image directly into a cell
- `⌘C` on a selected occupied cell copies content back to clipboard
- Right-click on empty cell → context menu: Paste
- Right-click on occupied cell → context menu: Delete content, More (TBD)

### Storage
- On first launch, creates `~/Library/Application Support/Bundle/Bundles/`
- Each bundle gets a UUID-named subdirectory
- When content is dropped into a cell, it is **moved** (not copied) into the bundle's directory
- Plain text pasted from clipboard is saved as a `.txt` file
- Each bundle directory contains a `manifest.json` tracking:
  - Bundle name, grid dimensions
  - Cell index → filename mapping
  - Content type per cell
  - Display name per cell
- On launch, `BundleManager` reads all bundle directories, reconstructs state from manifests
- All content is safe on disk if app crashes

### Thumbnails
- File/folder — native macOS icon via `NSWorkspace`
- Image — actual image preview rendered inline
- Plain text — text document icon, first ~25 characters shown as name

**Files introduced:** `CellState`
**Files modified:** `BundleManager`, `BundleGridView`, `CellView`, `BundleState`

**Done when:** user can paste and drag files into cells, content survives app restart, files live in app support directory.

---

## v0.5 — Drag out & copy out
**Goal:** getting content back out of a cell.

- Drag from an occupied cell back to Finder or any app — behaves like a normal system drag
- Uses `NSFilePromiseProvider` or `NSDraggingSource` for proper AppKit drag-out
- Cell is only cleared after a confirmed non-cancelled drop
- `⌘C` on selected cell copies the file URL to clipboard (already in v0.4, verified here)
- Delete content via right-click removes file from cell and sends it to Trash via `NSWorkspace.recycle`

**Files modified:** `CellView`, `BundleManager`

**Done when:** files can be dragged back out to Finder and deleted cleanly.

---

## v0.6 — Polish & animations
**Goal:** the app feels premium and complete.

- Bundle panel appear/disappear animation (fade or subtle scale)
- Cell fill animation when content is dropped in
- Cell clear animation when content is deleted
- `⌘⌥B` show/hide is animated across all panels
- Off-screen bundle recovery — if a bundle's saved position is outside all current screen bounds (e.g. external display disconnected), auto-move to main display on launch
- Empty state — if user has no bundles, menu bar popover shows a prompt to create one
- Visual QA pass — corner radius, blur material, spacing, typography all consistent

**Done when:** app feels polished enough to use daily.

---

## Future / TBD
- Context menu "More" items (TBD in v0.4)
- Horizontal grid orientation toggle
- iCloud sync for bundles across Macs
- Onboarding flow for first launch
