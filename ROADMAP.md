# Bundle — Roadmap

## Architecture overview
9 files, one job each:

| File | Responsibility |
|---|---|
| `BundleApp` | `@main` entry point, `MenuBarExtra`, owns `BundleManager` as `@State` |
| `HotkeyManager` | Registers and fires `⌘⌥B` global hotkey, nothing else |
| `BundleManager` | `@Observable` — single source of truth, owns all `BundleState` objects and `BundlePanelController` instances, handles create/delete/save/load |
| `BundlePanelController` | NSPanel wrapper — one per bundle, hosts SwiftUI content, owns drag/move/resize |
| `BundleGridView` | SwiftUI grid of cells + `:::` handle + settings popover for a given bundle |
| `CellView` | Individual cell — empty and occupied states |
| `GridSizePicker` | Shared table-insert size picker (1×1–5×5), used by creation page and settings |
| `MenuBarView` | MenuBarExtra popover content, NavigationStack lives here |
| `Models` | `BundleState` (@Observable class) + `CellState` (struct) + `BundleLayout` (shared panel geometry) |

**Key decisions:**
- No `AppDelegate` — `MenuBarExtra` (macOS 13+) handles the menu bar natively in SwiftUI
- `BundleState` is a **class** (required for `@Observable`)
- `CellState` is a **struct** (value type, lives inside `BundleState`)
- Position saves to `manifest.json` — not `UserDefaults`. One source of truth per bundle.
- File I/O is async via `async/await`
- Bundle discovery on launch by scanning the Bundles directory — no separate index file

---

## v0.1 — Foundation ✅ (2026-06-04)
**Goal:** prove the overlay concept. App exists, hotkey fires, panel appears.

- macOS app with no dock icon (`LSUIElement = true` in Info.plist)
- `BundleApp` sets up `MenuBarExtra` — icon appears in menu bar (no popover yet)
- `⌘⌥B` global hotkey registered via `HotkeyManager`
- One hardcoded `BundlePanelController` created on launch
- Panel is a floating `NSPanel` — frosted glass material, rounded corners, correct visual aesthetic from day one
- Hardcoded 1x3 grid of empty cells renders inside the panel
- Hotkey shows and hides the panel

**Files introduced:** `BundleApp`, `HotkeyManager`, `BundlePanelController`, `BundleGridView`, `CellView`
**Temporary scaffold:** `AppCoordinator` — owns the hardcoded panel + hotkey wiring for v0.1 only. Replaced by `BundleManager` in v0.2.

**Done when:** app lives in menu bar, `⌘⌥B` toggles a frosted glass panel with empty circles.

---

## v0.2 — Bundle creation ✅ (2026-06-07)
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

## v0.3 — Bundle positioning & settings ✅ (2026-06-08)
**Goal:** bundles are movable and configurable.

- Title row: bundle **name** label (small, muted, left, truncating) + `:::` grip on the
  right. Rename updates the label live (`@Observable`); blank name shows "Untitled".
- `:::` handle renders at the top of each bundle panel
- **Hold + drag** on handle moves the panel anywhere on screen — uses absolute
  `NSEvent.mouseLocation` (not gesture translation, which jitters as the window
  moves under the cursor)
- **Click** on handle opens settings popover:
  - Rename — bound to `bundle.name`, panel header updates live (`@Observable`)
  - Change size — re-opens the shared `GridSizePicker`, rebuilds the cell grid and
    resizes the panel top-anchored (`BundleLayout.panelSize`)
  - Delete — `BundleManager.deleteBundle` closes the panel and drops the state
- `⌘⌥B` correctly shows/hides ALL panels simultaneously (unchanged from v0.2)

**⚠️ Persistence deferred to v0.4 — intentional.** Position now lives in memory on
`BundleState.position`: the drag handler and resize write to it, and `show()` reads
it (centering on first show). But there is no disk layer yet, and bundles themselves
are in-memory only, so position does **not** survive relaunch — there is nothing to
restore onto. v0.4 adds `manifest.json`; persisting position is then a one-line save
at the two `// v0.4: persist` markers in `BundlePanelController` + a load in
`BundleManager`. Building a throwaway position-persistence path now was rejected.

**Files modified:** `BundlePanelController`, `BundleGridView`, `BundleManager`, `Models`
**Files introduced:** `GridSizePicker` (extracted from `MenuBarView` so the settings
popover can reuse it); `BundleLayout` added to `Models`

**Implementation notes:**
- Borderless `NSPanel` can't become key, which would block the rename field from
  typing. `BundlePanelController` uses a `KeyablePanel: NSPanel` subclass overriding
  `canBecomeKey`; `.nonactivatingPanel` keeps it from stealing focus / activating the app.
- Click vs drag on the handle: `.onTapGesture` (settings) coexists with
  `DragGesture(minimumDistance: 4)` (move) — a still click stays a tap.
- `BundleLayout` centralizes cell/gap/pad/handle geometry so the SwiftUI layout and
  the AppKit panel frame can't drift apart.

**Done when:** bundles are draggable, settings rename/resize/delete all work, and the
bundle name shows as a header label. ✅ (Position persistence across relaunch lands with
storage in v0.4.)

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
