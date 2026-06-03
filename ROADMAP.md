# Bundle — Roadmap

## Architecture overview
8 files, one job each:

| File | Responsibility |
|---|---|
| `BundleApp` | `@main` entry point, `MenuBarExtra`, owns `BundleManager` as `@State` |
| `HotkeyManager` | Registers and fires `⌘⌥B` global hotkey, nothing else |
| `BundleManager` | `@Observable` — single source of truth, owns all `BundleState` objects and `BundlePanelController` instances, handles create/delete/save/load |
| `BundlePanelController` | NSPanel wrapper — one per bundle, hosts SwiftUI content inside |
| `BundleGridView` | SwiftUI grid of cells for a given bundle |
| `CellView` | Individual cell — empty and occupied states |
| `MenuBarView` | MenuBarExtra popover content, NavigationStack lives here |
| `Models` | `BundleState` (@Observable class) + `CellState` (struct) — always used together |

**Key decisions:**
- No `AppDelegate` — `MenuBarExtra` (macOS 13+) handles the menu bar natively in SwiftUI
- `BundleState` is a **class** (required for `@Observable`)
- `CellState` is a **struct** (value type, lives inside `BundleState`)
- Position saves to `manifest.json` — not `UserDefaults`. One source of truth per bundle.
- File I/O is async via `async/await`
- Bundle discovery on launch by scanning the Bundles directory — no separate index file

---

## v0.1 — Foundation
**Goal:** prove the overlay concept. App exists, hotkey fires, panel appears.

- macOS app with no dock icon (`LSUIElement = true` in Info.plist)
- `BundleApp` sets up `MenuBarExtra` — icon appears in menu bar (no popover yet)
- `⌘⌥B` global hotkey registered via `HotkeyManager`
- One hardcoded `BundlePanelController` created on launch
- Panel is a floating `NSPanel` — frosted glass material, rounded corners, correct visual aesthetic from day one
- Hardcoded 1x3 grid of empty cells renders inside the panel
- Hotkey shows and hides the panel

**Files introduced:** `BundleApp`, `HotkeyManager`, `BundlePanelController`, `BundleGridView`, `CellView`

**Done when:** app lives in menu bar, `⌘⌥B` toggles a frosted glass panel with empty circles.

---

## v0.2 — Bundle creation
**Goal:** user can create real bundles from the menu bar.

- Menu bar icon opens a translucent SwiftUI popover (`MenuBarExtra`)
- Popover home screen:
  - `+ Add new bundle`
  - Show / Hide (mirrors `⌘⌥B`)
  - Quit
- `+ Add new bundle` pushes to creation page via `NavigationStack`
- Creation page:
  - Text field for custom bundle name
  - Table Grid picker — select dimensions from 1x1 up to 5x5
  - Create button
- Hitting Create:
  - `BundleManager` creates a new `BundleState`
  - New `BundlePanelController` instantiated, panel appears on screen
  - Popover closes
- Multiple bundles can exist simultaneously
- Hardcoded panel from v0.1 is removed

**Files introduced:** `MenuBarView`, `BundleManager`, `Models`

**Done when:** user can create multiple named bundles with different grid sizes from the menu bar.

---

## v0.3 — Bundle positioning & settings
**Goal:** bundles are movable and configurable.

- `:::` handle renders at the top of each bundle panel
- **Hold + drag** on handle moves the panel anywhere on screen
- Position saves to `manifest.json` on drag end
- Position restores on next launch
- **Click** on handle opens settings popover:
  - Rename — updates panel header live
  - Change size — re-opens Table Grid picker, resizes cell grid
  - Delete — removes panel from screen, deletes bundle directory from disk
- `⌘⌥B` correctly shows/hides ALL panels simultaneously

**Files modified:** `BundlePanelController`, `BundleGridView`, `BundleManager`, `Models`

**Done when:** bundles are draggable, position persists, all three settings actions work.

---

## v0.4 — Cell interaction & storage
**Goal:** cells accept content and everything persists on disk.

Built together — interaction without storage means rewriting it anyway.

### Cell interaction
- One-click selects a cell — blue ring, all others deselect
- Clicking empty space or another cell deselects
- `⌘V` on a selected empty cell pastes clipboard content in
- Drag any file, folder, or image directly into a cell
- `⌘C` on a selected occupied cell copies content back to clipboard
- Right-click on empty cell → Paste
- Right-click on occupied cell → Delete content, More (TBD)

### Storage
- On first launch, creates `~/Library/Application Support/Bundle/Bundles/`
- Each bundle gets a UUID-named subdirectory
- Content dropped into a cell is **moved** (not copied) into the bundle's directory
- Plain text pasted from clipboard is saved as a `.txt` file
- Each bundle directory contains a `manifest.json`:
  - Bundle name, grid dimensions, screen position
  - Cell index → filename mapping
  - Content type and display name per cell
- On launch, `BundleManager` scans the Bundles directory and reconstructs state from each `manifest.json`
- App crash safe — all content is on disk

### Thumbnails
- File/folder — native macOS icon via `NSWorkspace`
- Image — actual image preview rendered inline
- Plain text — text document icon, first ~25 characters as name

**Files modified:** `BundleManager`, `BundleGridView`, `CellView`, `Models`

**Done when:** user can paste and drag content into cells, everything survives app restart.

---

## v0.5 — Drag out & copy out
**Goal:** getting content back out of a cell.

- Drag from an occupied cell back to Finder or any app — normal system drag
- Uses `NSDraggingSource` for proper AppKit drag-out
- Cell only clears after a confirmed non-cancelled drop
- Delete content via right-click sends file to Trash via `NSWorkspace.recycle`

**Files modified:** `CellView`, `BundleManager`

**Done when:** files drag back out to Finder cleanly and delete correctly.

---

## v0.6 — Polish & animations
**Goal:** the app feels premium and complete.

- Bundle panel appear/disappear animation (fade or subtle scale)
- Cell fill and clear animations
- `⌘⌥B` show/hide animated across all panels
- Off-screen bundle recovery — auto-move to main display if saved position is outside all screen bounds
- Empty state in popover when no bundles exist yet
- Visual QA — corner radius, blur material, spacing, typography all consistent

**Done when:** app feels polished enough to use daily.

---

## Future / TBD
- Context menu "More" items
- Horizontal grid orientation toggle
- iCloud sync across Macs
- Onboarding flow for first launch
