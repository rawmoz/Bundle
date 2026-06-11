# Bundle — Claude Context

## What this is
A macOS overlay utility that lets users create named Bundles — floating panels that live on the desktop. Each Bundle contains Cells (circular slots) that hold files, folders, images, or plain text. Press `⌘⌥B` to toggle all bundles on/off.

## Core concepts

**Bundle (internal Swift type: `BundlePanel`)**
A named floating panel. Multiple bundles can exist simultaneously, each freely positioned anywhere on the desktop. Position is saved and restored on launch.
Note: `Bundle` is a reserved type in Swift/Foundation (`Bundle.main` etc.), so all internal model and UI types use the name `BundlePanel` to avoid compiler conflicts.

**Cell (internal Swift type: `BundleCell`)**
An empty container — like an unoccupied lot. One-click selects it (turns blue). Once selected, the user fills it by pasting (`⌘V`), dragging content in, or right-click → Paste. Once occupied it shows a thumbnail and the item's name underneath.

## Creating a Bundle
1. Click menu bar icon → popover opens
2. Click "+ Add new bundle" → popover navigates to creation page (inline, NavigationStack)
3. Enter a custom name (e.g. "School Stuff")
4. Pick a size via the Table Grid picker — any configuration from 1x1 up to 5x5 (columns x rows)
5. Hit Create → bundle appears on screen, popover closes

## Grid layout
Bundles are true 2D grids. The user selects dimensions at creation (e.g. 1x5, 3x2, 4x3). Max size is 5x5. The grid determines the number of cells — a 3x2 grid has 6 cells. Grid size can be changed later via bundle settings.

## Bundle header (`:::` handle)
- **Hold + drag** — moves the bundle anywhere on the desktop, position saves automatically
- **Click** — opens the bundle settings popover:
  1. Rename
  2. Change Bundle size (re-opens the Table Grid picker)
  3. Delete

## Cell interaction model

**One-click**
Selects the cell (blue ring). A selected cell can:
- Receive a paste (`⌘V`) — file, folder, image, or plain text from clipboard
- Receive a drag — drag any content directly into the cell
- Be copied from — `⌘C` copies the cell's content back to clipboard
- Be navigated from — **arrow keys** move the selection around the grid (full 2D, edge-
  stops, no wrap) — see v0.8
- Be previewed — **spacebar** opens a native macOS Quick Look preview of an occupied cell's
  content, toggling closed on a second press — see v0.8

**Right-click on empty cell**
- Paste

**Right-click on occupied cell**
- Delete content
- More (TBD)

## Cell content types
Each cell holds one item. Thumbnail and name display underneath:

| Type | Thumbnail | Name shown |
|---|---|---|
| File (PDF, doc, etc.) | Native macOS file icon via NSWorkspace | Filename |
| Folder | Native macOS folder icon via NSWorkspace | Folder name |
| Image (PNG, JPG, etc.) | Actual image preview | Filename |
| Plain text | Text document icon | First ~25 characters of content |

## Storage model
One master `Bundles/` folder holds one UUID-named subdirectory per BundlePanel. Each holds
a `manifest.json` (name, columns, rows, position, and an array of occupied cells → content
type / stored filename / display name; empty cells omitted) plus the cell content files.
The human bundle name lives in the manifest, **not** the folder name (names aren't unique,
can be renamed, may contain illegal chars). Plain text is saved as a `.txt`. Every change
writes the manifest immediately (tiny, atomic), so a crash never loses content.

**The app is sandboxed**, so the real path is the container, not the plain `~/Library`:
```
~/Library/Containers/com.danielramos.Bundle/Data/Library/Application Support/Bundle/
  Bundles/
    [bundle-uuid]/
      manifest.json
      [cell content files and folders]
```
`FileManager`'s app-support URL resolves to this container automatically — code uses that,
never a hard-coded path.

### Move vs. delete semantics
A **move** relocates bytes (the leftover copy is redundant → removed permanently). A
**delete** destroys content with no destination → goes to the **Trash** (recoverable).
- **Drag in** = move: `moveItem` the source into the bundle. If the sandbox blocks the
  rename, copy in then permanently `removeItem` the source (Trash only as a last resort).
- **Drag out** = move: deliver to the drop destination, then permanently delete the
  bundle's copy.
- **Paste (⌘V)** = copy — the clipboard only lends a reference, source left untouched.
- **Right-click Delete Content / Delete Bundle / shrink-grid drop** = **Trash**.

Requires the **`files.user-selected.read-write`** entitlement to remove a dragged-in file
from its source — declared in an explicit `Bundle/Bundle.entitlements` (the
`ENABLE_USER_SELECTED_FILES = readwrite` build setting silently emitted *read-only*).

## Hotkey behavior
`⌘⌥B` toggles ALL bundles simultaneously — one press shows all, next press hides all.

## Positioning
Free positioning — bundles float anywhere on screen. User drags via the `:::` handle. Position persists per bundle and is restored on next launch. If a bundle's saved position is off-screen (e.g. external display disconnected), it auto-moves to the main display on next launch.

## Visual design
Translucent frosted glass panels — Apple premium aesthetic. Rounded corners, dark translucent material (SwiftUI `.ultraThinMaterial` or similar), feels native and minimal. No heavy chrome. Think system control center vibes.

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer
- **AppKit** — window management, floating NSPanels
- **NSWorkspace** — native file icons and image thumbnails
- **QuickLook** — native spacebar preview of cell content (`QLPreviewPanel`, v0.8)
- **Carbon** — global hotkey registration (`⌘⌥B`)
- **Xcode** — IDE and build tool
- **GitHub** — version control (`github.com/rawmoz/Bundle`)

## Working style
- User is a vibe coder — Claude writes all code, user runs it in Xcode and reports back
- Keep files small and focused, one feature per file where possible
- User pastes errors from Xcode, Claude fixes them
- Do not hard-code values that are meant to be configurable later
- Update this file at the end of every session

## Menu bar
App lives as a menu bar icon (no dock icon). Clicking it opens a small translucent popover — same frosted glass aesthetic as the bundles:
- + Add new bundle
- Show / Hide (mirrors `⌘⌥B`)
- Quit

## Implementation notes

### Global hotkey (HotkeyManager)
`InstallApplicationEventHandler` from Carbon is unavailable in modern Swift — the UPP-style function pointer it requires is not bridged. The working pattern:
1. `RegisterEventHotKey` to register `⌘⌥B` globally (this IS available in Swift)
2. `NSEvent.addLocalMonitorForEvents(matching: .systemDefined)` to detect firing — Carbon routes the hotkey event to our own app queue as a `.systemDefined` event with `subtype.rawValue == 6`

No Accessibility permissions required. Works in sandboxed apps.

### Panel setup
`NSPanel` with `.borderless + .nonactivatingPanel` style mask. Size comes from `BundleLayout.panelSize(columns:rows:)` (in `Models.swift`) — the single source of the cell/gap/pad/handle geometry, shared by the SwiftUI layout and the AppKit panel frame so they can't drift. Cell size 64pt matches macOS Control Center small widget size. The panel height includes the `:::` handle row above the grid.

### Positioning & settings (v0.3)
- The panel's title row is the bundle **name** (small, muted, left, truncating) with the `:::` grip on the right. Only the grip is interactive; the name is a passive label and shows "Untitled" when `bundle.name` is empty.
- Drag-to-move lives on the `:::` handle only. `BundlePanelController` repositions the panel from absolute `NSEvent.mouseLocation` (plus a mouse-to-origin offset captured at drag start), **not** the SwiftUI gesture translation — translation jitters because moving the window shifts the view under the cursor.
- Click (not drag) on the handle opens the settings popover (rename / change size / delete). `.onTapGesture` coexists with `DragGesture(minimumDistance: 4)`.
- Rename binds straight to `bundle.name` (`@Observable`, updates live). Change size calls `bundle.resize(...)` then `applyResize()` which resizes the panel top-anchored. Delete routes through `controller.onRequestDelete` → `BundleManager.deleteBundle`.
- **Rename text field needs a key window.** Borderless panels can't become key by default, so `BundlePanelController` uses a `KeyablePanel: NSPanel` subclass overriding `canBecomeKey`. `.nonactivatingPanel` means becoming key doesn't activate the app or steal focus.
- **Position is in-memory only in v0.3.** `BundleState.position` is written on drag-end and resize and read on first `show()`, but there's no disk layer yet and bundles don't survive relaunch — see "Storage model" / v0.4. Two `// v0.4: persist to manifest.json here` markers in `BundlePanelController` flag where the save goes.

### Cell interaction & storage (v0.4)
- **`BundleStore`** owns all disk I/O and the `manifest.json` format. **`SelectionStore`**
  (`@Observable`) tracks the single app-wide selected cell — transient, never persisted.
- **Selection / keyboard:** clicking a cell selects it (blue ring) and makes its panel key;
  a local `NSEvent` keyDown monitor in `BundleManager` then routes `⌘V`/`⌘C` to it. The
  panel resigning key (click desktop / another app) clears the selection, guarded so
  selecting a cell in another bundle doesn't wipe the new selection.
- **Drag-IN file detection reads the file URL off the drag pasteboard**
  (`NSPasteboard(name: .drag)`), NOT item-provider type loading. PDFs expose
  `public.file-url` but image files often don't, so item-provider approaches saved a copy
  and never removed the original. `loadInPlaceFileRepresentation` surfaced the file but
  leaked a `.tmp` staging folder in the sandbox — both rejected.
- **Drag-OUT uses a file promise** (`NSItemProvider.registerFileRepresentation`), not a raw
  `NSURL` drag — dragging a URL out of the sandbox container throws Finder error -8058. The
  promise's load handler fires only on an accepted drop, so a cancelled drag clears nothing;
  on success it's a move (bundle copy permanently deleted via `moveOutContent`).
- **`resize` preserves cell content by index** (grow appends empty trailing slots, shrink
  trims). The grid guards `if index < bundle.cells.count` to survive the resize transition
  (fixed an out-of-bounds crash). Shrinking that would drop *filled* cells shows a confirm
  alert; confirming trashes those files.
- `BundleStore.ingest` runs `nonisolated` static helpers (`uniqueName`) since file ops may
  run off the main actor; the rest of the store is main-actor by default isolation.

### State ownership (v0.2, persistence added v0.4)
`AppCoordinator` is gone. `BundleManager` (`@Observable`, held as `@State` in `BundleApp`) is the single source of truth — it owns every `BundleState`, the matching `BundlePanelController` keyed by UUID, the `HotkeyManager`, the `SelectionStore`, and the `BundleStore`. `createBundle` builds the state, spins up a controller, shows it, and saves; on launch it loads every `manifest.json` and restores positions. `toggleAll` shows/hides every panel together.

### Menu bar popover (v0.2)
`MenuBarExtra` uses `.menuBarExtraStyle(.window)` so the popover hosts a real SwiftUI view (`MenuBarView`) with a `NavigationStack`. Home → "Add new bundle" pushes the creation page (name field + a table-insert-style `GridSizePicker`, 1×1 up to 5×5). `.window` style has no official dismiss API; after Create we call `NSApp.keyWindow?.close()` to collapse the popover.

## Roadmap
See `ROADMAP.md` for the full versioned build plan.

## Repo
Local: /Users/danielramos/dev/Bundle
Remote: https://github.com/rawmoz/Bundle
