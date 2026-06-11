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

## v0.4 — Cell interaction & storage ✅ (2026-06-09)
**Goal:** cells accept content and everything persists on disk.

Built together — interaction without storage means rewriting it anyway. **Drag-out and
the move/delete semantics from v0.5 were pulled forward and also shipped here** (see
below) — v0.5 is now effectively done.

### Cell interaction
- One-click selects a cell — blue ring; selecting elsewhere deselects. Selection is a
  single app-wide cell (`SelectionStore`), transient (never persisted).
- Clicking empty panel space **or losing key focus** (desktop / another app) deselects.
- `⌘V` on a selected empty cell pastes clipboard content in; `⌘C` on a selected occupied
  cell copies it back out. A local `NSEvent` keyDown monitor routes these — selecting a
  cell makes its panel key, the same trick the rename field uses.
- Drag any file, folder, or image into a cell.
- Right-click empty cell → Paste; right-click occupied cell → Delete Content.

### Storage
- On first launch, creates the Bundles directory. **NOTE: the app is sandboxed**, so the
  real path is the container: `~/Library/Containers/com.danielramos.Bundle/Data/Library/
  Application Support/Bundle/Bundles/` (not the plain `~/Library/...` the model implies).
  `FileManager`'s app-support URL resolves to the container automatically.
- Each bundle gets a UUID-named subdirectory (the human name lives in the manifest, not
  the folder name — names aren't unique, can be renamed, and may contain illegal chars).
- `manifest.json` per bundle: name, columns, rows, position, and an array of occupied
  cells (index → content type, stored filename, display name). Empty cells are omitted.
- On launch, `BundleManager` scans the directory and rebuilds every `BundleState`; `show()`
  restores the saved position. Position persists on drag-end and resize.
- `BundleState.resize(...)` **preserves** cell content by index (grow appends empty trailing
  slots, shrink trims trailing slots) instead of rebuilding.
- Crash-safe — every change writes the manifest immediately (tiny, atomic, synchronous).

### Thumbnails
- File/folder — native macOS icon via `NSWorkspace`; image — inline preview; text — doc
  icon + first ~25 chars as the name. All render inside the fixed 64pt `CellView`.

### Move vs. delete semantics (the important model)
A **move** relocates bytes; the leftover copy is redundant and removed permanently. A
**delete** destroys content with no destination, so it goes to the **Trash** (recoverable).
- **Drag in** = real move: `moveItem` the source into the bundle (no copy, no Trash). If
  the sandbox blocks the rename, copy in then permanently `removeItem` the source; trashing
  is only a last resort if even deletion is denied.
- **Drag out** = real move: deliver the file to the drop destination, then permanently
  delete the bundle's copy.
- **Paste (⌘V)** = copy (the clipboard only lends a reference) — source left untouched.
- **Right-click Delete Content / Delete Bundle / shrink-grid drop** = **Trash**.

### Implementation notes / gotchas hit this session
- **User-selected read-write entitlement is required** to remove a dragged-in file from
  its source folder. The `ENABLE_USER_SELECTED_FILES = readwrite` build setting silently
  still emitted *read-only*, so we switched to an explicit `Bundle/Bundle.entitlements`
  (`CODE_SIGN_ENTITLEMENTS`) declaring sandbox + `files.user-selected.read-write`.
- **Drag-IN file detection reads the file URL straight off the drag pasteboard**
  (`NSPasteboard(name: .drag)`), NOT item-provider type loading. PDFs expose
  `public.file-url`, but image files frequently don't, so item-provider approaches saved a
  copy and never removed the original. `loadInPlaceFileRepresentation` *did* surface the
  file but leaked a `.tmp` staging folder in the sandbox — rejected.
- **Drag-OUT uses a file promise** (`NSItemProvider.registerFileRepresentation`), not a raw
  `NSURL` drag — dragging a URL out of the sandbox container throws Finder error -8058. The
  promise's load handler fires only on an accepted drop, so a cancelled drag clears nothing.
- **Shrink-grid safety:** picking a size that would drop *filled* cells shows a confirm
  alert ("Make this bundle smaller?"); confirming trashes those cells' files. A bounds
  guard in the grid (`if index < bundle.cells.count`) fixes a crash during the resize
  transition where the row/col range briefly outran the trimmed cells array.

**Files introduced:** `BundleStore`, `SelectionStore`, `Bundle.entitlements`
**Files modified:** `Models`, `BundleManager`, `BundlePanelController`, `BundleGridView`,
`CellView`, `project.pbxproj`

**Done when:** ✅ paste/drag content in, drag/copy out, everything survives restart.

---

## v0.5 — Drag out & copy out ✅ (done early, with v0.4)
**Goal:** getting content back out of a cell.

Shipped as part of v0.4 — see the "Move vs. delete semantics" and gotchas above.
- Drag from an occupied cell back to Finder / any app — via `NSItemProvider` file promise
  (avoids the -8058 sandbox-container drag error).
- Cell only clears after a confirmed, non-cancelled drop; drag-out is a **move** (bundle's
  copy permanently removed), not a copy.
- `⌘C` copies an occupied cell's content back to the clipboard.
- Delete Content (right-click) and Delete Bundle send to the **Trash** (recoverable).

**Done when:** ✅ files drag back out to Finder cleanly and delete correctly.

---

## v0.6 — Polish & animations
**Goal:** the app feels premium and complete.

- Bundle panel appear/disappear animation (fade or subtle scale)
- Cell fill and clear animations
- `⌘⌥B` show/hide animated across all panels
- Off-screen bundle recovery — auto-move to main display if saved position is outside all screen bounds
- Empty state in popover when no bundles exist yet
- **Reveal in Finder** — a menu item (bundle settings, and right-click on an occupied
  cell) that opens that bundle's folder in Finder via
  `NSWorkspace.activateFileViewerSelecting(...)`. The single seamless way for a user to
  reach/recover their actual files without ever typing a path. **Path-agnostic by design:**
  it reveals whatever folder `BundleStore` computes at runtime (`directory(for:)`), so it's
  automatically correct per-user and whether the app is sandboxed (container path) or not
  (clean `~/Library` path). Never hard-code the location.
- Visual QA — corner radius, blur material, spacing, typography all consistent

**Done when:** app feels polished enough to use daily.

---

## v0.7 — Cell rearrange (drag between cells)
**Goal:** drag a cell's content onto another cell to move it — within a bundle or across
bundles — without round-tripping through Finder.

### Behavior
- **Empty target → move:** content moves to the target cell; the source cell empties.
- **Occupied target → swap:** the two cells exchange contents (never destroys anything).
- Works **within a bundle and across bundles** (drag a cell from bundle A onto a cell in
  bundle B).

### Why it's additive, not a rewrite
- This is an **internal** drag — it never leaves the app, so none of the external
  drag machinery applies (no file promise, no -8058, no sandbox concerns).
- The cell drag already exists (drag-out); we **also** register a private pasteboard
  payload `(sourceBundleID, sourceIndex)` on it. A receiving cell checks for that payload
  first and handles it internally; absent it, the existing file/image/text-from-outside
  path runs unchanged. One drag serves both Finder-drop and cell-drop.
- **Within a bundle:** no file I/O — just swap the two `CellState` entries in
  `BundleState.cells` and save the manifest.
- **Across bundles:** move the file from bundle A's folder to bundle B's folder (reuse
  `BundleStore` copy/remove primitives) and update both manifests. `BundleManager` owns
  every bundle, so it coordinates the A→B handoff in one place.
- No window/ownership/storage-model changes. `BundleManager` stays the single source of truth.

### Care points
- The source cell must clear **only after** a confirmed internal drop (mirror the drag-out
  rule), so a cancelled drag changes nothing.
- A cross-bundle move is a real move (source bundle's file removed once the copy lands),
  consistent with the move/delete semantics in v0.4.

**Files likely touched:** `CellView`, `BundleGridView`, `BundleManager`, `BundleStore`

**Done when:** dragging a cell onto another moves (empty) or swaps (occupied) its content,
within and across bundles, with nothing lost on a cancelled drag.

---

## v0.8 — Keyboard navigation & Quick Look preview
**Goal:** drive a selected cell entirely from the keyboard — move the selection with the
arrow keys, and hit space to preview the cell's content exactly like Finder.

Both features hang off the **same insertion point**: the local `NSEvent` keyDown monitor in
`BundleManager` (`installKeyboardMonitor`) that already routes `⌘V`/`⌘C` to the selected
cell. Selecting a cell makes its panel key, so the monitor fires; these are two more
branches in it. Today that monitor guards on `.command` — it must be restructured so
modifier-less keys (arrows, space) are also handled.

### Arrow-key navigation
- With a cell selected, the arrow keys move the selection within that bundle's grid:
  - **Up** = `index - columns`, **Down** = `index + columns` (the grid is a flat array, so
    one row is a single column-stride).
  - **Left** = `index - 1`, **Right** = `index + 1`, with row-boundary edge-stops so Left
    on the first column and Right on the last column don't wrap into the adjacent row.
- **Full 2D, all four arrows** — chosen so every cell is reachable in any grid (up/down
  alone leaves the other columns of a multi-column grid unreachable).
- **Edge-stop:** a move that would leave the grid is ignored (Up when `index < columns`,
  Down when `index + columns >= cells.count`, Left/Right at the row edges). The selection
  simply stays put — no wrap, no beep.

### Why it's additive, not a rewrite
- Pure selection math — no file I/O, no persistence, no panel changes, no new frameworks.
- It only calls `selection.select(bundleID:index:)`; the blue ring moves. Selection is
  already a single app-wide index (`SelectionStore`), and `columns`/`rows` already live on
  `BundleState`, so the move is computed from data we already hold.

### Spacebar Quick Look preview
- With an **occupied** cell selected, **space** opens the native macOS Quick Look preview
  of that cell's file — the floating mini-window for PDFs, images, folders, and text, byte-
  for-byte the Finder-spacebar behavior. Space again **toggles it closed** (native).
- Space on an **empty** cell does nothing (event swallowed so the system doesn't beep).
- We already hold the real on-disk URL for any occupied cell
  (`BundleManager.contentURL(for:cell:)`); Quick Look just needs that URL via a small
  data-source object. All four content types preview natively — `.txt` for text, the image,
  the folder's large icon, the PDF/doc — matching Finder.

### Care points
- **Quick Look from an accessory app is the one real unknown.** The app is a menu-bar
  `LSUIElement` with **borderless, non-activating** panels. `QLPreviewPanel` normally drives
  itself through the responder chain (`acceptsPreviewPanelControl`), which assumes a
  conventional key-window app. Expect to **present and manage the panel manually** (set its
  `dataSource` directly, `makeKeyAndOrderFront`) rather than relying on the responder chain.
  Known-solvable, but validate it first — this is the v0.8 equivalent of the -8058 gotcha.
- Restructuring the keyDown monitor must not regress `⌘V`/`⌘C`: keep the command branch and
  add the modifier-less arrow/space branches alongside it, all still guarded by "a cell is
  selected."
- No storage, model, or window-ownership changes. `BundleManager` stays the single source
  of truth and keeps owning keyboard routing.

**Files likely touched:** `BundleManager` (monitor), `SelectionStore` or `Models` (a small
move helper, optional). **Files likely introduced:** a `QuickLookController`
(`QLPreviewPanelDataSource`/`Delegate`).

**Done when:** with a cell selected, the arrow keys move the blue ring around the grid and
stop at every edge, and space opens (and re-closes) a native Quick Look preview of an
occupied cell's content.

---

## Future / TBD
- Context menu "More" items
- Horizontal grid orientation toggle
- iCloud sync across Macs
- Onboarding flow for first launch
- Finder-friendly folder names — fold the bundle name into the on-disk folder as
  `Name — shortUUID` (keep the UUID as the real key) instead of UUID-only. Optional nicety;
  the "Reveal in Finder" item (v0.6) makes this largely unnecessary.

## v1.0 — Distribution (decision pending, not yet planned)
Getting it to other people. **No deployment plan was ever decided** — the sandbox is just
the Xcode template default we discovered mid-v0.4, not a chosen strategy. Decide this once,
before shipping; new users start fresh, so there's no data migration for *them* (only this
dev machine's test bundles, which are throwaway).
- **Pick a route:**
  - **Mac App Store** — sandbox *required* (stays on); storage stays in the container forever
    (fine — users never see it). Needs an Apple Developer account + App Store review.
  - **Direct download** (site / GitHub release) — sandbox *optional*; turning it off gives
    the clean `~/Library/Application Support/Bundle/` path automatically (code already uses
    `FileManager`, no path is hard-coded). Needs Developer ID signing + **notarization** so
    Gatekeeper doesn't block it.
- **Either route needs an Apple Developer account ($99/yr).** Running it on your *own* Mac
  is free forever; the fee is only for friction-free download by others.
- If sandbox is turned off: write a one-time migration to move existing bundles out of the
  container to the new path (matters only for dev/test data, not first-time users).
