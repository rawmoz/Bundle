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

## v0.6 — Robustness & Reveal in Finder ✅ (2026-06-18)
**Goal:** close the functional gaps that make the app safe and complete to use daily —
no cosmetics. (Animations and the visual-consistency pass were split out to **v0.9**: it's
wasted effort to polish UI and freeze typography/spacing while v0.7/v0.8 are still adding
interactions. Polish lands once the feature set is frozen.)

- **Off-screen bundle recovery** ✅ — `BundlePanelController.show()` runs the saved origin
  through `onScreenOrigin(for:)`: if the panel's frame intersects no current display's
  `visibleFrame` (e.g. an external display was disconnected), it recenters on the main
  display and **persists the rescue** (`onPersist`) so it sticks; a frame still touching any
  screen is left exactly as saved. A robustness fix, not a nicety. *(Implemented; not
  user-verified — needs an actual display disconnect to trigger.)*
- **Reveal in Finder** ✅ — opens a folder in Finder via
  `NSWorkspace.activateFileViewerSelecting(...)`. The single seamless way for a user to
  reach/recover their actual files without ever typing a path. Three surfaces:
  - **Bundle settings** popover → `revealBundleFolder(_:)` selects that bundle's folder.
  - **Right-click an occupied cell** → `revealContent(bundle:index:)` highlights that file.
  - (Pre-existing) menu-bar top-level → `revealBundlesFolder()` opens the whole `Bundles/`.
  **Path-agnostic by design:** all reveal whatever `BundleStore` computes at runtime
  (`directory(for:)` / `contentFileURL`), so they're automatically correct per-user and
  whether the app is sandboxed (container path) or not (clean `~/Library` path). Never
  hard-code the location.
- **Empty state in the popover** ✅ — `HomeMenu` shows a friendly prompt (grid icon, "No
  bundles yet", one-line invite) above the menu rows when `manager.bundles.isEmpty`, instead
  of a bare list. *(Implemented; not user-verified — only visible with zero bundles.)*

**Files touched:** `BundleManager` (`revealBundleFolder`/`revealContent`),
`BundlePanelController` (`onScreenOrigin`), `BundleGridView` + `CellView` (reveal closures +
menu/button), `MenuBarView` (empty prompt).

**Done when:** ✅ a disconnected display never strands a bundle, users can jump to their files
in Finder (confirmed working on cells + settings), and a first-launch popover isn't
empty-looking.

---

## v0.7 — Cell rearrange (drag between cells) ✅ (2026-06-11)
**Goal:** drag a cell's content onto another cell to move it — within a bundle or across
bundles — without round-tripping through Finder.

**Double-click to open shipped here too** — double-clicking an occupied cell opens its
content in the default app via `NSWorkspace.open` (single-click still selects; the
`count: 2` tap gesture is ordered before the `count: 1` one so it isn't swallowed).

### Behavior
- **Empty target → move:** content moves to the target cell; the source cell empties.
- **Occupied target → swap:** the two cells exchange contents (never destroys anything).
- Works **within a bundle and across bundles** (drag a cell from bundle A onto a cell in
  bundle B).

### Why it's additive, not a rewrite
- This is an **internal** drag — it never leaves the app, so none of the external
  drag machinery applies (no file promise, no -8058, no sandbox concerns).
- **Within a bundle:** no file I/O — just `swapAt` the two `CellState` entries in
  `BundleState.cells` and save the manifest (covers both move-onto-empty and swap).
- **Across bundles:** `BundleStore.moveContentBetweenBundles` relocates the file from
  bundle A's folder to bundle B's (plain `moveItem` — both are in our container) and both
  manifests are updated. `BundleManager` owns every bundle, so it coordinates A→B in one
  place. No window/ownership/storage-model changes; `BundleManager` stays the source of truth.

### Implementation note — the plan's pasteboard payload did NOT work
The original plan was to tag the drag with a private `(bundleID, index)` pasteboard
payload and read it back on drop. **This failed:** SwiftUI hands the drop an **empty
`NSItemProvider`** for in-app drags — `registeredTypeIdentifiers` comes back `[]`, so the
payload can't be read off either the provider or the drag pasteboard (the representation
is lazy). The drag pasteboard *does* advertise the type (so `.onDrop` still fires and
highlights), but the bytes never arrive.
**What works instead:** record the source cell **in memory** (`BundleManager.pendingCellDrag`)
the moment its drag begins (the `.onDrag` closure runs at drag start, wired through
`onBeginDragCell`). On drop, if `pendingCellDrag` is set *and* there's no real Finder file
in the drag (`dragFileURL() == nil`, so an external file always wins), it's an internal
rearrange. `pendingCellDrag` is cleared on every drop and on drag-out, and overwritten at
each new drag start, so a cancelled drag can't hijack a later external drop. A `.bundleCell`
`UTType` (exported at runtime) is still registered/accepted — only so the drop *fires*; the
in-memory value does the real work.

### Care points (met)
- The source cell clears **only** inside the target's drop handler — a cancelled drag
  changes nothing.
- A cross-bundle move is a real move (source file removed once it lands), consistent with
  the move/delete semantics in v0.4.

**Files touched:** `Models` (`CellDragPayload`, `UTType.bundleCell`), `CellView`,
`BundleGridView`, `BundlePanelController`, `BundleManager`, `BundleStore`.

**Done when:** ✅ dragging a cell onto another moves (empty) or swaps (occupied) its
content, within and across bundles, with nothing lost on a cancelled drag.

---

## v0.8 — Keyboard navigation & Quick Look preview ✅ (2026-06-15)
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

### Care points (met)
- **Quick Look from an accessory app was the one real unknown — and it's handled by driving
  the panel manually.** The app is a menu-bar `LSUIElement` with **borderless,
  non-activating** panels, so there's no reliable responder-chain controller
  (`acceptsPreviewPanelControl`). `QuickLookController` sets the shared `QLPreviewPanel`'s
  `dataSource`/`delegate` directly and `NSApp.activate(...)` + `makeKeyAndOrderFront` (the
  activate is needed or the preview opens behind the frontmost app). `import Quartz`;
  `NSURL` conforms to `QLPreviewItem`.
- **The real gotcha was selection survival, not presentation (the v0.8 -8058 equivalent).**
  Making the QL panel key makes the bundle panel resign key, and the v0.4
  `didResignKeyNotification` handler clears the selection on focus-loss — so the blue ring
  vanished the moment the preview opened (Finder keeps the file selected behind Quick Look).
  Fix: that handler now bails when `QLPreviewPanel.sharedPreviewPanelExists() &&
  .isVisible`, so the cell stays selected behind the preview and real focus-loss (desktop /
  another app) still deselects.
- **`⌘V`/`⌘C` did not regress.** The monitor resolves the selected cell first, then splits
  into a `.command` branch (unchanged) and a modifier-less arrow/space branch that rejects
  only command/control/option (arrow keys carry `.function`/`.numericPad`, so an empty-flag
  requirement would never match).
- **Space stays typeable in the rename field.** The modifier-less branch bails when the key
  window's first responder `is NSText`, so a cell selected behind the settings popover
  doesn't let space get swallowed mid-typing.
- No storage, model, or window-ownership changes. `BundleManager` stayed the single source
  of truth and kept owning keyboard routing.

**Files introduced:** `QuickLookController`. **Files touched:** `BundleManager` (monitor
split + `moveSelection`/`previewSelectedCell`), `BundlePanelController` (resign-key guard).

**Done when:** ✅ with a cell selected, the arrow keys move the blue ring around the grid and
stop at every edge, and space opens (and re-closes) a native Quick Look preview of an
occupied cell's content, with the cell staying selected behind the preview.

**Also added here:** `⌘⌫` on a selected occupied cell trashes its content (recoverable),
matching Finder — one more branch in the same keyDown monitor, reusing `deleteContent`.

---

## v0.9 — Polish & animations ✅ (2026-06-18)
**Goal:** make the app *feel* premium and finished — the do-last pass, deliberately
scheduled after the feature set is frozen (v0.6–v0.8). Doing this earlier means re-polishing
every time a new interaction lands, so it waits until there's nothing left to add.

### Centralized style tokens — the structural half of the "visual QA pass"
- **`BundleStyle`** (new file) is the look-and-feel source of truth, the sibling of
  `BundleLayout` (geometry). Every color, corner radius, material, font, ring width, and
  animation routes through it. This *is* the consistency pass made structural: the values
  are provably identical across panels / cells / header / popover, and a future restyle is
  a one-file change instead of a hunt through every view. `CellView` and `BundleGridView`
  magic numbers were all replaced with `BundleStyle` references (visuals unchanged, just
  consolidated). Motion constants live under `BundleStyle.Motion` so timing is tunable in
  one place.

### Panel appear/disappear fade — and ⌘⌥B animated for free
- **`BundlePanelController.show()`/`hide()`** animate the panel's `alphaValue` via
  `NSAnimationContext`. Because `toggleAll` already drives **every** panel through these,
  `⌘⌥B` fades the whole set together with no extra code — one motion path shared by toggle,
  launch restore, and create.
- **Re-entrancy is handled:** re-showing a panel that's still mid-fade-out animates alpha
  back up (no flicker, no snap to transparent — only a fully off-screen panel resets to 0),
  and the fade-out's completion re-checks `alphaValue` before `orderOut` so an interrupting
  show can't yank the panel away underneath itself.
- **Chose fade over a panel scale, deliberately.** A show/hide *scale* would need
  layer anchor-point manipulation on the borderless `NSHostingView`, which is fragile and
  risks breaking panel layout — exactly the corner to avoid. Panels fade (the goal allowed
  "fade or subtle scale"); the *cells* carry the scale motion where SwiftUI owns the anchor
  safely.

### Cell fill/clear animation
- **`CellView`** animates the empty↔occupied switch off observable `cell.isEmpty`, so a
  fill or clear from *anywhere* — paste, drop, delete, drag-out, cross-cell rearrange —
  animates through the same path. Occupied content pops in with a scale-up-from-center +
  opacity transition (`.scale(scale: 0.55).combined(with: .opacity)`); a cleared cell fades
  back to the empty slot. A quick hover-highlight fade was added on drag-over too
  (`BundleStyle.Motion.cellHover`).

### Title typography bump (designer pass on the bundle name)
- The bundle name was `.caption` (~11pt, regular, 60% white) — it read as a *label*, not a
  *title*. Bumped to **14pt semibold at 85% white** so it sits one clear step above the
  content in hierarchy without shouting; the `:::` grip stays at 45% white so the contrast
  *is* the hierarchy. `BundleLayout.headerHeight` 18→22 gives the larger text breathing room
  so it never clips (centralized, so the AppKit panel frame and SwiftUI layout stay in sync;
  existing panels just grow 4pt taller, top-anchored, on next launch).

### Tuning knobs (all single-line)
- Fade duration → `BundleStyle.Motion.panelFadeDuration` (0.22s)
- Cell pop spring → `BundleStyle.Motion.cellContent` (response 0.32, damping 0.72)
- Title size/weight/brightness → `BundleStyle.headerFont` / `headerColor`
- Header height → `BundleLayout.headerHeight`

**Files introduced:** `BundleStyle`. **Files touched:** `BundlePanelController` (alpha
fade), `CellView` (transitions + tokens), `BundleGridView` (tokens), `Models` (headerHeight).

**Done when:** ✅ panels fade in/out (including ⌘⌥B across all of them), cells animate on
fill/clear, the bundle title reads as a proper title, and every visual constant lives in one
place. *(Implemented + builds clean; animation feel pending live confirmation in Xcode.)*

---

## Misc changes after v0.9 (unplanned, ad-hoc)
Small one-off features added on request, not planned milestones — tagged "v0.10" in commits
and documented in CLAUDE.md: split header (title top / drag + gear buttons bottom), cell
rename on disk + red Delete Content, and human-readable bundle folder names.

---

## v0.11 — Multi-file paste (spill fill) ✅ (2026-06-19)
**Goal:** pasting multiple files at once fills multiple cells instead of silently keeping
only the first. Today, copying 2 (or 8) files and `⌘V`-ing into a cell pastes **only the
first** — the rest are dropped silently. That's the actual bug this fixes.

### Behavior
- **Spill-fill in reading order.** Start at the **selected cell**, then walk *forward*
  through the grid filling one file per empty cell. The grid is a flat **row-major** array
  (`index = row * columns + col`), so ascending index order *is* left→right, top→bottom
  ("like a book") — no new geometry needed, it falls out of the existing layout.
- **Skip occupied cells.** If a later cell is already occupied, skip it and continue to the
  next empty one (don't stop dead at the first occupied cell). Pasting 4 files when cells 0
  and 2 are taken fills 1, 3, 4, 5. The selected cell itself must be empty to start (same
  guard as today).
- **Forward only, from the selection.** Fill from the selected cell onward; do **not** wrap
  backward to fill empty cells *before* the selection (backward-fill is surprising). So
  selecting the top-left cell before a big paste becomes the natural "fill everything"
  gesture.
- **Single file → unchanged.** One file behaves exactly like today (fills the selected
  cell). Fully backward-compatible.

### Edge cases
- **More files than empty cells (overflow) → all-or-nothing.** If the whole batch can't fit
  in the empty cells forward of the selection, **paste nothing** and show a notice (e.g.
  "Not enough room for 8 — only 5 free"). *(Shipped decision — the original plan was to fill
  what fits and notice the rest; a partial fill was confusing, so it's all-or-nothing.* This
  matters for v0.12: drag-in is a **move**, and all-or-nothing means a batch that can't fully
  fit never relocates anything off the source.) Either way nothing is lost — paste is a copy.
- **No empty cells at all** (full bundle, or a full cell selected) → nothing pastes; brief
  notice / beep so it's not a confusing no-op.
- **Mixed file types in one paste** (PDFs + images + folders together) → already handled.
  Finder hands them all over as file URLs and `ingestURL` auto-detects image-vs-file-vs-
  folder per item, so no special casing.

### Why it's additive, not a rewrite
- Contained to **one function** — `paste(into:index:)` in `BundleManager`. The change is
  `urls.first` → a loop over `urls` that advances to the next empty cell each time (same for
  the images array; text is always single).
- **Both paste surfaces get it for free** — the `⌘V` keyDown monitor and the right-click
  Paste menu item both call this one function.
- **Batch the save** — ingest all N items, then write the manifest **once** at the end
  instead of N atomic writes.
- Selection stays on the originally selected cell (least surprising). No model, storage, or
  window changes.

**Files touched:** `BundleManager` (`paste` spill engine + all-or-nothing notice),
`Toast.swift` (new — the frosted notice), `BundlePanelController` (expose `frame` to anchor
the toast).

**Done when:** ✅ copying N files and pasting into a cell fills N empty cells in reading order
starting from the selection, skipping occupied cells; if the whole batch won't fit, nothing
is pasted and a toast says how many cells are free. The fill engine (`spillFill`) is shared,
ready for v0.12 drag-in to reuse.

---

## v0.12 — Multi-file drag-in (spill fill, part 2) ✅ (2026-06-19)
**Goal:** dragging multiple files onto a cell spreads them across cells exactly like the
v0.11 paste — same "fill empty cells in reading order from the drop target" behavior. Today
a multi-file drag, like paste, keeps only the first.

### Why it's the second half, after v0.11
- **Reuses v0.11's fill engine.** v0.11 builds the core spill logic (forward walk, skip
  occupied, overflow notice, batched save) in the clean, contained **paste** path. v0.12
  feeds that same engine from **dragged** URLs instead of clipboard URLs — the fill behavior
  is identical, only the *source* of the URLs differs.
- **Drag is the messier path**, which is why it goes second. It reads off the **drag**
  pasteboard (`NSPasteboard(name: .drag)`) and carries the existing drag history — the -8058
  sandbox-container error, the drag-OUT file promise, and the in-memory `pendingCellDrag`
  used for internal cell→cell rearrange (v0.7). Building the spill logic in the easy path
  first, then applying it here, keeps those two concerns from tangling.
- **Internal rearrange is unaffected.** A cell→cell drag carries no real file URL
  (`dragFileURL() == nil`) and is dispatched by the in-memory `pendingCellDrag`, so the
  multi-file spill only applies to **external** files dragged in from Finder — single-cell
  move/swap behavior stays exactly as in v0.7.

### Behavior (mirrors v0.11)
- Start at the **drop-target cell**, fill forward through empty cells in row-major reading
  order, skipping occupied cells.
- **Overflow** → fill what fits, notice the rest. Drag-in is a **move** (not a copy), so any
  files that don't fit must be **left at their source untouched** — only the ones that
  actually land in a cell are moved/removed. (This is the one real difference from paste,
  where leftovers are always safe because paste never touches the source.)
- Single dragged file → unchanged (fills the drop-target cell, as today).

### Care points
- **Move semantics on overflow** — only relocate the bytes for files that found a cell; a
  file with no destination is never removed from its source (consistent with v0.4: a move
  needs a real destination, otherwise nothing happens to the original).
- Reuse the v0.11 fill helper rather than re-deriving the walk, so paste and drag-in can't
  drift apart.

**Files touched (actual):** `BundleManager` only — `drop(...)` routes dragged file URLs
through the v0.11 `spillFill` engine with `move: true`, and `dragFileURL()` became
`dragFileURLs()` (whole array off the drag pasteboard). The planned `CellView`/`BundleGridView`
changes weren't needed: the URLs are read off the drag pasteboard, not the `NSItemProvider`
array the views pass through, so the view layer is untouched.

**Done when:** ✅ dragging N files from Finder onto a cell fills N empty cells in reading order
from the drop target, skipping occupied cells. Per the v0.11 all-or-nothing decision, a batch
that won't fully fit is dropped entirely — and because drag-in is a **move**, that means
nothing is relocated off the source unless the whole batch lands. The internal cell→cell
rearrange (v0.7) is unaffected — it carries no file URLs, so `dragFileURLs().isEmpty` still
routes it through `pendingCellDrag`.

---

## v0.13 — Resize keeps grid orientation
**Goal:** changing a bundle's size — in **either dimension, columns and/or rows, together or
separately** — keeps each cell's content in the **same visual position**. Today, shrinking (or
growing) the grid can reflow content that the resize didn't visually touch, because content is
preserved by **flat array index**, not by `(row, col)`.

### The bug
`BundlePanel.resize` (in `Models.swift`) preserves cells **by index**: it `prefix`-trims or
appends trailing slots on the flat `cells` array. But the flat index encodes position as
`index = row * columns + col`, so the moment **`columns` changes** every item's `(row, col)`
remaps and the whole grid reflows. (Changing **only `rows`** — same column count — is the one
case that happens to survive today, since trailing flat slots *are* the bottom rows; but the
fix must handle row and column changes uniformly, including both at once.) Examples that should
*not* reflow untouched cells: dropping the rightmost column of a 3×N grid (columns 0…n−2 stay
put), trimming the bottom row, or shrinking both at once (e.g. 4×4 → 3×3 keeps the top-left 3×3
block exactly where it is).

### Behavior
- **Preserve by `(row, col)`, not by flat index.** On resize, map each occupied cell from its
  old `(row, col)` to the *same* `(row, col)` in the new grid. A cell whose row or column no
  longer exists in the smaller grid is the only content affected.
- **Shrink** drops only the cells that fall **outside** the new bounds (the trimmed rightmost
  columns / bottom rows) — every cell still inside keeps its exact spot.
- **Grow** keeps every existing cell in place and the new cells appear empty (bottom/right).
- **Dropped-content guard stays.** The existing confirm-before-trashing-filled-cells alert
  (v0.4) still applies, but now it triggers on cells outside the new 2D bounds, not trailing
  flat-array slots.

### Why it's contained
- The fix lives in **`resize`** — rebuild `cells` as a new `columns × rows` array, copying
  each old cell into `newIndex = row * newColumns + col` when `row < newRows && col < newColumns`.
- No storage format change: the manifest already stores cells by index; it's just written
  from the correctly-remapped array. No window/UI change beyond what already redraws on resize.

**Files touched (planned):** `BundlePanel.resize` (`Models.swift`); possibly the shrink-confirm
check in `BundleManager` if it counts dropped cells.

**Done when:** resizing a bundle leaves every cell still within the new bounds in its original
visual position — shrinking the grid only removes the trimmed edge cells, and growing only adds
empty ones, with no reflow of untouched content.

---

## v1.1 — Custom storage location (idea, tied to v1.0 distribution)
**Goal:** let the user choose *where* their bundles live — e.g. `~/Documents/Bundle`
instead of the hidden sandbox container — so the files are reachable in a place of their
choosing. Surfaced as a setting (and/or an onboarding step), defaulting to today's
location so nothing breaks for existing setups.

### Why it's mostly easy, with one hard part
- **The location is a single chokepoint.** Everything in `BundleStore` derives from one
  property, `bundlesURL`, set once in `init()`. Pointing the app at a different folder is
  a one-line change; `directory(for:)`, `save`, `loadAll`, `ingest`, Trash, and cross-
  bundle move all flow from it. Reveal in Finder (v0.6) only gets *better*.
- **The sandbox is the cost.** An arbitrary user folder (Documents, etc.) needs
  **security-scoped bookmarks**: pick the folder via `NSOpenPanel` (the
  `files.user-selected.read-write` entitlement already covers this), but the grant
  evaporates on quit — so create a `.withSecurityScope` bookmark, persist the bookmark
  *data* (UserDefaults), and on **every launch** resolve it and
  `startAccessingSecurityScopedResource()` before any I/O, holding the scope for the app's
  whole lifetime (resolve once at launch, never stop until quit).

### Scope of work
- A small `StorageLocation` helper: bookmark create / persist / resolve, plus a
  "change location" flow.
- `BundleStore` takes a resolved root URL instead of hardcoding application-support.
- **Migration:** when the location changes, `moveItem` the existing UUID subfolders from
  the old root into the new one (or existing bundles appear to vanish).
- **Always nest a `Bundle/` subfolder** inside the chosen location, so picking
  `~/Documents` directly doesn't dump UUID folders loose into Documents.
- Settings entry (and optionally a first-launch onboarding step).

### Risk / unknown
- The one real unknown — same flavor as the -8058 gotcha — is holding a security scope
  for a borderless, non-activating `LSUIElement` app. Should be fine (scope is file-level,
  not tied to a key window), but validate it first.

### Decision interaction with v1.0
- **Mac App Store route** → sandbox mandatory → the bookmark dance above is required.
- **Direct-download (notarized) route** → sandbox can be dropped → this feature becomes
  trivial (just a path in UserDefaults, no bookmarks at all). So if direct distribution
  wins, this is nearly free. **Decide v1.0 first; it sets how much of this is needed.**

**Done when:** the user can pick a folder for their bundles, it persists across relaunches,
existing bundles migrate cleanly, and the default keeps current setups working untouched.

---

## Future / TBD
- Emoji in bundle names — the rename field's SwiftUI `.popover` is `.transient`, so the fn
  emoji picker (a separate window) steals focus and dismisses it. Fix needs a manually
  presented `NSPopover` with `.applicationDefined` behavior. Workaround today: paste an emoji.
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
