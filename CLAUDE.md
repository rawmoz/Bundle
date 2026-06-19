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

## Bundle controls (title top, buttons bottom)
The bundle **name** sits in a row at the **top** of the panel. The two controls — a
`:::` drag handle and a ⚙ gear button — live in a row pinned to the **bottom** of the
panel, on the right, always below the grid regardless of grid size (v0.10).
- **`:::` drag handle — drag** moves the bundle anywhere on the desktop, position saves
  automatically. Drag-only (no tap behavior).
- **⚙ gear button — click** opens the bundle settings popover (opens upward):
  1. Rename
  2. Change Bundle size (re-opens the Table Grid picker)
  3. Reveal in Finder — opens the bundle's folder (v0.6)
  4. Delete

## Cell interaction model

**One-click**
Selects the cell (blue ring). A selected cell can:
- Receive a paste (`⌘V`) — file, folder, image, or plain text from clipboard
- Receive a drag — drag any content directly into the cell
- Be copied from — `⌘C` copies the cell's content back to clipboard
- Be deleted — `⌘⌫` trashes a selected occupied cell's content (recoverable), like Finder — v0.8
- Be rearranged — drag an occupied cell onto another cell to **move** (empty target) or
  **swap** (occupied target), within a bundle or across bundles — see v0.7

**Double-click**
Opens an occupied cell's content in its default app (`NSWorkspace.open`), like Finder.
- Be navigated from — **arrow keys** move the selection around the grid (full 2D, edge-
  stops, no wrap) — v0.8
- Be previewed — **spacebar** opens a native macOS Quick Look preview of an occupied cell's
  content, toggling closed on a second press; the cell stays selected behind the preview — v0.8

**Right-click on empty cell**
- Paste

**Right-click on occupied cell**
- Reveal in Finder — highlights the cell's file in its bundle folder (v0.6)
- Rename… — renames the **actual file on disk** (keeps the extension), not just the
  label; a small popover takes the new name (v0.10)
- Delete Content — shown in **red** to flag it as destructive (trashes the file, v0.10)
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
One master `Bundles/` folder holds one subdirectory per BundlePanel. Each holds a
`manifest.json` (name, columns, rows, position, and an array of occupied cells → content
type / stored filename / display name; empty cells omitted) plus the cell content files.
The **UUID inside the manifest is the canonical identity** — folders are named after the
human bundle name for Finder readability (v0.10), but the name is *derived* from the
manifest, never the source of truth. Plain text is saved as a `.txt`. Every change writes
the manifest immediately (tiny, atomic), so a crash never loses content.

**Folder naming (v0.10):** folders used to be UUID-named; now `BundleStore` keeps a folder
named after the bundle (sanitized + uniquified), renaming it on disk whenever the bundle is
renamed. See "Human-readable bundle folders" under Implementation notes for the full design,
the one-way (in-app name → folder) sync direction, and why renaming in Finder isn't supported.

**The app is sandboxed**, so the real path is the container, not the plain `~/Library`:
```
~/Library/Containers/com.danielramos.Bundle/Data/Library/Application Support/Bundle/
  Bundles/
    [Bundle Name]/        ← named after the bundle (was [bundle-uuid] pre-v0.10)
      manifest.json       ← holds the canonical UUID + name
      [cell content files and folders]
```
`FileManager`'s app-support URL resolves to this container automatically — code uses that,
never a hard-coded path.

**Custom storage location (planned, v1.1):** the location is a single chokepoint —
`BundleStore.bundlesURL`, set once in `init()`; everything else derives from it. The idea
is to let the user pick where bundles live (e.g. `~/Documents/Bundle`) via a setting /
onboarding step, defaulting to the current container. The hard part is the sandbox: an
arbitrary folder needs **security-scoped bookmarks** (persist the bookmark data, resolve +
`startAccessingSecurityScopedResource()` on every launch). Becomes trivial if v1.0 ships
non-sandboxed (direct download). See ROADMAP "v1.1 — Custom storage location".

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
- **`resize` preserves cell content by `(row, col)`** — see v0.13 (it preserved by flat
  *index* through v0.12, which re-flowed the grid on any column change). Grow adds empty
  cells at the bottom/right, shrink drops only the trimmed edge. The grid guards
  `if index < bundle.cells.count` to survive the resize transition (fixed an out-of-bounds
  crash). Shrinking that would drop *filled* cells shows a confirm alert; confirming trashes
  those files.
- `BundleStore.ingest` runs `nonisolated` static helpers (`uniqueName`) since file ops may
  run off the main actor; the rest of the store is main-actor by default isolation.

### Cell rearrange & double-click open (v0.7)
- **Internal cell→cell drag** moves (empty target) or swaps (occupied target) content,
  within a bundle (`cells.swapAt`, no file I/O) or across bundles
  (`BundleStore.moveContentBetweenBundles` — plain `moveItem`, both folders are in our
  container, so no -8058 / sandbox concern).
- **The source can't travel on the drag.** SwiftUI delivers an **empty `NSItemProvider`**
  for in-app drags (`registeredTypeIdentifiers == []`), so the planned pasteboard payload
  was unreadable. Instead the source cell is recorded **in memory**
  (`BundleManager.pendingCellDrag`) when its `.onDrag` fires (`onBeginDragCell`); the drop
  reads it. Guarded by `dragFileURL() == nil` so a real Finder file always wins, and
  cleared on every drop / drag-out / new drag start so a cancelled drag can't hijack a
  later drop. A runtime-exported `.bundleCell` `UTType` is still registered + accepted by
  `.onDrop` — only so the drop *fires* for an internal drag; the in-memory value does the work.
- **Double-click** an occupied cell → `BundleManager.openContent` opens it in the default
  app. The `count: 2` tap gesture is ordered **before** the `count: 1` select gesture.

### Robustness & Reveal in Finder (v0.6, shipped after v0.7/v0.8)
- **Off-screen recovery** lives in `BundlePanelController.show()`: the saved origin is run
  through `onScreenOrigin(for:)`, which recenters on `NSScreen.main` only when the panel's
  frame intersects no screen's `visibleFrame` (a display was unplugged). The corrected
  origin is written back to `bundle.position` and persisted via `onPersist` so the rescue
  sticks; a frame still touching any screen is returned unchanged.
- **Reveal in Finder** is three `NSWorkspace` calls on `BundleManager`, all path-agnostic
  (they reveal whatever `BundleStore` computes at runtime, never a hard-coded path):
  `revealBundlesFolder()` (menu-bar, opens the whole `Bundles/`),
  `revealBundleFolder(_:)` (settings popover, `activateFileViewerSelecting` the bundle dir),
  `revealContent(bundle:index:)` (occupied-cell right-click, selects the file). Wired to the
  views as `onRevealBundle` / `onRevealCell` closures through `BundlePanelController` exactly
  like the existing cell-action closures.
- **Empty-state prompt** is a conditional `emptyPrompt` view in `HomeMenu`, shown above the
  menu rows when `manager.bundles.isEmpty` (SwiftUI tracks the `@Observable` read).

### Keyboard navigation & Quick Look (v0.8)
- **One keyDown monitor, two branches.** `BundleManager.installKeyboardMonitor` now
  resolves the selected cell first, then splits: a `.command` branch (the v0.4 `⌘V`/`⌘C`,
  unchanged) and a modifier-less branch for arrows/space. The modifier-less branch rejects
  only command/control/option — arrow keys carry `.function`/`.numericPad`, so requiring an
  empty flag set would never match.
- **Arrow navigation** is pure selection math (`moveSelection`): the grid is a flat array,
  so up/down is a ±`columns` stride and left/right is ±1 with row-edge stops (`column == 0`
  / `column == columns-1`). Out-of-grid moves are ignored — the ring stays put, no wrap, no
  beep. No file I/O, no persistence.
- **Spacebar Quick Look** (`previewSelectedCell` → `QuickLookController`): toggles a native
  `QLPreviewPanel` of an occupied cell's on-disk URL. Empty cell → `contentURL` is nil so
  nothing opens, but the event is still swallowed so there's no beep.
- **Quick Look is driven manually, not via the responder chain.** As an `LSUIElement` with
  borderless non-activating panels there's no reliable responder-chain controller, so
  `QuickLookController` sets the panel's `dataSource`/`delegate` directly and
  `NSApp.activate(...)` + `makeKeyAndOrderFront` (otherwise the preview can open behind the
  frontmost app). `import Quartz`; `NSURL` conforms to `QLPreviewItem`.
- **Gotcha — selection must survive the preview (the v0.8 equivalent of the -8058 lesson).**
  Making the QL panel key makes the bundle panel resign key, which the v0.4
  `didResignKeyNotification` handler treats as focus-loss and clears the selection — so the
  blue ring vanished the instant the preview opened. Fix: that handler now bails when
  `QLPreviewPanel.sharedPreviewPanelExists() && .isVisible`, so the cell stays selected
  behind the preview (Finder parity) and real focus-loss still deselects.
- **Don't swallow space while typing.** The modifier-less branch bails when the key window's
  first responder `is NSText`, so space stays typeable in the rename field (a cell can still
  be selected behind the settings popover).

### Polish & animations (v0.9)
- **`BundleStyle` is the look-and-feel source of truth** — the sibling of `BundleLayout`
  (geometry). Every color, corner radius, material, font, ring width, and animation routes
  through it; `CellView`/`BundleGridView` hold no raw style numbers. A restyle is a one-file
  change. Motion constants live under `BundleStyle.Motion`.
- **Panel fade = animated `alphaValue`** in `BundlePanelController.show()`/`hide()` via
  `NSAnimationContext`. `toggleAll` already routes every panel through these, so `⌘⌥B` fades
  all panels together with no extra code. Re-entrancy: `show()` only resets alpha to 0 when
  the panel was fully off-screen (re-showing mid-fade just animates back to 1, no flicker),
  and `hide()`'s completion re-checks `alphaValue == 0` before `orderOut` so an interrupting
  show can't pull the panel out from under itself.
- **No panel *scale*, on purpose** — a show/hide scale needs layer anchor-point hacking on
  the borderless `NSHostingView` (fragile, can break layout). Panels fade; the cell pop-in
  carries the scale where SwiftUI owns the anchor.
- **Cell fill/clear animates off `cell.isEmpty`** (`.animation(value:)` in `CellView`), so
  every fill/clear path (paste, drop, delete, drag-out, rearrange) animates through one
  place. Occupied content uses `.scale(scale: 0.55).combined(with: .opacity)`; cleared cells
  fade. Drag-hover highlight has its own quick fade keyed on `isTargeted`.
- **Bundle title** is 14pt semibold @ 85% white (was `.caption`/60%); the grip stays 45% so
  the contrast carries the hierarchy. `BundleLayout.headerHeight` 18→22 for breathing room —
  centralized, so the AppKit frame and SwiftUI layout don't drift.

### Split controls — title top, buttons bottom (v0.10)
- **The old single `:::` grip did double duty** (tap = settings, hold-drag = move). It's now
  **two dedicated buttons** in `BundleGridView`: `dragHandle` (the `:::` dots, drag-only) and
  `settingsButton` (a `gearshape.fill`, tap-only). Splitting them removes the click-vs-drag
  disambiguation entirely, so the drag handle uses `DragGesture(minimumDistance: 0)` —
  tracks from touch-down, no dropped-drag race (the v0.9 misc-fix concern is moot here).
- **Layout is now three rows**, not two: `titleRow` (name, top), `grid` (middle), `footer`
  (the two buttons, right-aligned, bottom). The footer is pinned to the bottom regardless of
  grid size because it's the last item in the `VStack`.
- **Geometry: added `BundleLayout.footerHeight` (16)** and grew `panelSize` by
  `gap + footerHeight` so the AppKit panel frame matches the extra bottom row and nothing
  clips. Still the single source of truth shared by SwiftUI + AppKit — they can't drift.
- **Settings popover opens upward** (`arrowEdge: .bottom`) since the gear is now at the
  bottom of the panel; a downward popover would fall off the bottom of the bundle/screen.

### Cell rename + red delete (v0.10)
- **Rename renames the file on disk**, not just the label. The chain mirrors the existing
  cell actions: `CellView` → `BundleGridView.onRenameCell(index, name)` →
  `BundlePanelController` → `BundleManager.renameContent` → `BundleStore.renameContentFile`.
  The store keeps the original extension, uniquifies the new base name against the folder
  (same `uniqueName` helper as ingest), and `moveItem`s in place. Manager then updates
  `storedFilename`; `displayName` follows the new filename for every type **except text**,
  whose label is a content preview, not the filename.
- **Rename UI is a popover with a `TextField`** anchored to the cell, prefilled with the
  current base name (no extension). The Rename menu item calls `onSelect()` first so the
  panel becomes key and the field is typeable — same key-window requirement as the settings
  rename (borderless `KeyablePanel`). Blank names are a no-op.
- **"Delete Content" is rendered red** via `Text(...).foregroundStyle(.red)` inside the
  destructive `Button` — the `role: .destructive` alone wasn't coloring it on this macOS.

### Human-readable bundle folders (v0.10)
- **Folders are now named after the bundle**, not the UUID, so `Bundles/` is readable in
  Finder. The UUID stays the canonical identity (it lives in `manifest.json`); the folder
  name is purely cosmetic and *derived* from the bundle name. Entirely contained to
  `BundleStore` plus one line in `BundleManager.loadSavedBundles`.
- **`folders: [UUID: String]` map** resolves id → current on-disk folder name. `directory(for:)`
  reads it (falls back to the UUID for an id not yet recorded — a new bundle is recorded by
  its first `save`). `loadAll` records each folder's actual name; `deleteDirectory` clears it.
- **`save()` is the single sync chokepoint.** It calls `reconcileFolder`, which renames the
  folder on disk when the name changed. Because in-app rename persists through `save`
  (settings popover `.onDisappear { onPersist() }`), the folder follows the name automatically.
- **Naming rules:** `sanitizeFolderName` strips `/ \ :`, leading dots, trims whitespace,
  falls back to `Untitled`. `desiredFolderName` adds a Finder-style ` 2`/` 3` suffix when the
  name collides with another bundle's folder *or any unrelated folder already on disk* — so a
  hand-made folder in `Bundles/` is stepped around, never clobbered.
- **Migration is automatic + lazy-safe.** `adoptHumanFolderNames(for:)` runs once at launch
  (after `loadAll`) and renames legacy UUID folders to human names. Idempotent — bundles
  already correctly named are untouched.
- **Failsafe:** a failed folder `moveItem` in `reconcileFolder` returns the *old* folder URL
  and leaves the map unchanged, so a rename that can't complete never strands content behind
  a freshly-created empty folder. A subdir without a readable `manifest.json` is skipped by
  `loadAll` (never loaded, never deleted), so junk in `Bundles/` is inert.
- **Sync is one-way (in-app name → folder), by design.** There's no folder watcher, so
  renaming a folder in Finder isn't picked up live and gets reverted to the bundle name on the
  next launch (manifest wins). A two-way sync would need an FSEvents watcher — deferred.

### Multi-file paste — spill fill (v0.11)
- **The bug it fixes:** `paste(into:index:)` read `urls.first` / `images.first`, so copying
  N files and `⌘V`-ing dropped all but the first **silently**. Now it reads the whole array
  and spreads it across cells.
- **`spillFill(_:into:from:ingest:)`** is the shared engine: it collects the empty cells at
  or after the selected cell in **row-major reading order** (`emptyCellIndices`) — ascending
  flat index *is* left→right, top→bottom — and ingests one item per cell, skipping occupied
  ones. Built generic on `T` with an `ingest` closure so **v0.12 drag-in reuses it** by
  feeding dragged URLs instead of clipboard URLs.
- **All-or-nothing (shipped decision, differs from the original ROADMAP).** If the empty
  cells forward of the selection can't hold the **whole** batch, nothing is placed and a
  toast says how many are free. (The plan was "fill what fits + notice the rest"; partial
  fills were confusing.) This also makes the move-based v0.12 safe for free — a batch that
  can't fully fit never relocates anything off its source.
- **Batched save.** `fillCell` and the three `ingest*` helpers gained `save: Bool = true`;
  the paste loop fills with `save: false` and writes the manifest **once** at the end instead
  of N times. Single-file paste/drop callers keep the default (save each time), unchanged.
- **The notice is a `Toast`** (`Toast.swift`) — a standalone borderless, click-through,
  floating `NSPanel` that fades a frosted capsule in over the bundle and dismisses itself.
  Decoupled from the grid so any call site can use it without threading through the cell
  closures; styled via `BundleStyle`. `BundlePanelController` exposes `frame` so the toast
  anchors above the right bundle. The full-cell-selected no-op still falls through to a
  system beep (the top guard returns false → `⌘V` un-handled), no toast needed there.

### Multi-file drag-in — spill fill, part 2 (v0.12)
- **The bug it fixes:** `drop(...)` read `dragFileURL()` (just `.first`), so dragging N files
  from Finder onto a cell silently kept only the first — the drag-in twin of the v0.11 paste
  bug. Now it reads every dragged URL and spill-fills them.
- **Reuses the v0.11 engine verbatim.** The file branch of `drop` now calls the same
  `spillFill(_:into:from:ingest:)` with `move: true`, so dragged files spread forward across
  empty cells from the drop target in row-major reading order, identical to paste — only the
  *source* of the URLs differs (drag pasteboard vs. clipboard). Single dragged file is
  unchanged (fills just the drop-target cell).
- **All-or-nothing makes the move safe for free.** `spillFill` checks capacity *before*
  ingesting anything, and `ingestURL(move: true)` (the copy-in-then-Trash-original) runs only
  for items that got a slot. So an overflowing batch places nothing and therefore moves
  nothing off its source — a file with no destination is never removed (v0.4 move semantics).
- **`dragFileURL()` → `dragFileURLs()`** now returns the whole `[URL]` off the drag
  pasteboard. The internal cell→cell precedence check just became `dragFileURLs().isEmpty` —
  an in-app rearrange (v0.7) still carries no file URLs and dispatches via `pendingCellDrag`,
  so it's completely untouched; the spill only applies to **external** Finder drags.
- **Contained to `BundleManager` alone.** The ROADMAP predicted `CellView`/`BundleGridView`
  changes, but because the URLs are read off the drag pasteboard — not the `NSItemProvider`
  array the views pass through — the view layer needed zero changes.

### Resize keeps grid orientation (v0.13)
- **The bug it fixes:** `BundlePanel.resize` preserved cells by **flat array index**
  (`prefix`-trim / append). Since `index = row * columns + col`, any change to `columns`
  remapped every cell's `(row, col)` and re-flowed the whole grid — e.g. dropping the right
  column of a 3×3 slid the top-right cell down to `(1,0)` instead of removing it. Changing
  only `rows` happened to survive (trailing flat slots *are* the bottom rows).
- **Fix — preserve by `(row, col)`.** `resize` (`Models.swift`) now rebuilds `cells` as a
  fresh `newColumns × newRows` array and copies each old cell into `row*newColumns+col`, but
  only when `row < newRows && col < newColumns`. The top-left block stays put; shrink drops
  only the trimmed rightmost columns / bottom rows; grow adds empty cells at the bottom/right.
- **The shrink-confirm had to move in lockstep.** `sizeChanged`/`commitSize`
  (`BundleGridView.swift`) shared a flat-index test (`>= newCount`) that would now count and
  trash the *wrong* cells. Both route through a new `droppedIndices()` helper using the same
  `row >= rows || col >= columns` test **against the old column count** (`bundle.columns`,
  read before `resize` runs), so the alert count and the trashed files match exactly what
  `resize` drops. The v0.4 confirm-before-trashing-filled-cells guard is unchanged in spirit
  — it just triggers on cells outside the new 2D bounds, not trailing flat slots.
- **No storage/format change.** The manifest still stores cells by index; it's just written
  from the correctly-remapped array. `resize` is the only place touched besides the confirm
  helper, and it has a single call site.

### Click-to-select latency (misc fix)
- **Symptom:** clicking a cell (even an empty one) took ~1s to show the blue ring, while
  arrow-key selection was instant. Cause: the cell had `.onTapGesture(count: 2)` (open) and
  `.onTapGesture(count: 1)` (select) — two SwiftUI tap gestures on one view force a wait for
  the double-click interval to elapse before the single tap can resolve. Arrow keys bypass
  gestures (pure `SelectionStore` math) so they never waited.
- **Fix:** select via `.simultaneousGesture(TapGesture().onEnded { onSelect() })` instead of
  a sibling `count:1` tap. A simultaneous gesture recognizes on the first click immediately
  (no disambiguation wait); a double-click harmlessly runs `onSelect()` then `onOpen()` on
  the same cell. Native AppKit apps feel instant for the same reason — they act on the click
  and read `clickCount`, never waiting for a maybe-second click. (A full mouse-down handler
  would be a hair faster still but needs an `NSViewRepresentable` bridge that risks the
  cell's existing `.onDrag`/`.onDrop`; the two-line simultaneous-gesture fix is enough.)

### State ownership (v0.2, persistence added v0.4)
`AppCoordinator` is gone. `BundleManager` (`@Observable`, held as `@State` in `BundleApp`) is the single source of truth — it owns every `BundleState`, the matching `BundlePanelController` keyed by UUID, the `HotkeyManager`, the `SelectionStore`, and the `BundleStore`. `createBundle` builds the state, spins up a controller, shows it, and saves; on launch it loads every `manifest.json` and restores positions. `toggleAll` shows/hides every panel together.

### Menu bar popover (v0.2)
`MenuBarExtra` uses `.menuBarExtraStyle(.window)` so the popover hosts a real SwiftUI view (`MenuBarView`) with a `NavigationStack`. Home → "Add new bundle" pushes the creation page (name field + a table-insert-style `GridSizePicker`, 1×1 up to 5×5). `.window` style has no official dismiss API; after Create we call `NSApp.keyWindow?.close()` to collapse the popover.

## Roadmap
See `ROADMAP.md` for the full versioned build plan.

## Repo
Local: /Users/danielramos/dev/Bundle
Remote: https://github.com/rawmoz/Bundle
