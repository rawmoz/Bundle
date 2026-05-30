# Bundle — Claude Context

## What this is
A macOS utility that gives users a temporary shelf for files mid-workflow. The user grabs a file, hits spacebar while dragging, a frosted glass panel slides in from the left edge of the screen, they drop the file into a circular slot, and retrieve it later via a global hotkey.

Think of it as a physical desk — a neutral staging area with no permanence implied. Not a folder, not a clipboard.

## Core interaction

There are two distinct triggers — they serve different moments and must never be confused:

**Trigger 1 — Spacebar mid-drag (putting a file in):**
1. User starts dragging a file or folder in Finder (or any app)
2. Hits spacebar WHILE the drag is active → shelf appears
3. User drops file into one of the circular slots
4. Shelf hides

**Trigger 2 — Global hotkey (getting a file back out):**
5. At any later time, user hits the global hotkey (TBD) → shelf opens
6. User drags file back out (behaves exactly like a normal system drag)
7. Shelf hides

Spacebar only works when macOS is in an active drag state. It does NOT trigger on hover, click, keyboard focus, or any other state. The global hotkey works regardless of drag state.

## Visual design
- **Panel** — frosted glass (SwiftUI material), floats anywhere on screen (not edge-anchored)
- **Panel position** — draggable by the user. Position persists via UserDefaults and is restored on next launch. Default starting position is left-center of the screen, but never hard-coded.
- **Slots** — 7 circular slots stacked vertically. Always visible. Empty slots show as faint empty circles.
- **File icon** — uses macOS native file icon via NSWorkspace (one line, auto-detects file type, shows real icon)
- **Minus button** — appears on each occupied slot, clears that file from the shelf (does NOT delete the file)
- **Future** — horizontal orientation toggle, customizable slot count. Build slots as a grid component so orientation is just a variable, not a rewrite.

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer, declarative
- **AppKit** — window management, floating panel
- **NSWorkspace** — native file icon detection
- **macOS Accessibility APIs** — detecting spacebar keypress during an active system drag from another app (e.g. Finder)
- **Xcode** — IDE, build tool
- **GitHub** — version control, public repo

## What was ruled out and why
- **Electron** — cannot detect spacebar pressed while a file is being dragged in another app (Finder). Requires OS-level access Electron doesn't have. Would have forced a degraded UX (open shelf first, then drag in — breaks the flow).
- **Shake gesture while dragging** — too easy to trigger accidentally, would get annoying fast.
- **Double click while dragging** — physically impossible, holding mouse button down prevents double click.
- **Menu bar app** — user didn't want this format.
- **React Native / Tauri** — unnecessary complexity, wrong tool for native Mac utility.
- **Hard-coded slot count** — 7 is the default but must be a variable from day one. Future setting.
- **Custom file type detector** — unnecessary, macOS gives real file icons for free via NSWorkspace.
- **Fixed edge anchoring** — ruled out in favor of a freely draggable panel with persistent position. Users know where they want things on their own screen.
- **CGEventTap for spacebar-mid-drag detection (v0.2)** — investigated exhaustively on macOS Sequoia. Two compounding problems: (1) pressing spacebar during a file drag triggers macOS "Show Desktop" at the window server level, which cannot be intercepted or swallowed via any CGEventTap location (cgSessionEventTap or cgHIDEventTap); (2) even with Accessibility permission granted and tap creation confirmed, the listen-only tap callback does not fire for events originating in other apps (Finder). This appears to be a Sequoia-era tightening of event tap access. v0.2 is parked until a viable approach is found.

## UX decisions
- Shelf floats **anywhere on screen** — position set by the user, not hard-coded
- Panel is **draggable via grip handle** — top of the panel has a dedicated drag handle (3-dot grip). `isMovableByWindowBackground = false` so slot drags don't move the window.
- **7 circular slots** stacked vertically (not hard-coded, variable)
- **Persists across launches** — files stay in storage, slot state saved to manifest.json on every change
- Dragging a file out behaves like a **normal system drag** (NSFilePromiseProvider)
- **Two distinct triggers** — see Core Interaction above. These are separate mechanisms, not interchangeable.
- **Spacebar mid-drag** — puts a file in. Only fires when macOS is in an active drag state. Never fires on hover, click, or focus.
- **Global hotkey ⌘⌥B** — opens/closes the shelf at any time
- **Slot interaction model (v0.4):** hover does nothing. Single click selects a slot (blue ring + fill). Return button (↩) appears on the selected slot only. Control held → trash icon on all occupied slots. Double-click opens the file in its default app. Selection resets when the panel closes.

## File storage strategy (decided in v0.3)
Using **move model**: files are physically moved into `~/Library/Application Support/Bundle/shelf/{uuid}/{filename}` on drop. Original location is recorded in a `manifest.json`. Shelf state persists across app launches.

**Slot action button (v0.4):**
- Selected slot shows `arrow.uturn.left` — moves file back to original location (falls back to Downloads if origin no longer exists)
- Control held: all occupied slots show `trash.fill` in red — sends file to Trash via NSWorkspace.recycle

**Drag-out:** uses AppKit `NSDraggingSource` (not SwiftUI `.onDrag`) so we get `draggingSession(_:endedAt:operation:)` callback. Slot is only cleared on confirmed non-cancel operation.

**To swap back to reference model**: only `ShelfStore.swift` — replace `drop(url:into:)` and `storageURL(at:)`. Nothing else in the app holds URLs directly.

**Naming conflicts**: each file lives in its own UUID subfolder so two `report.pdf` files never collide.

**Sandbox note**: if the app is ever sandboxed (App Store), raw path strings won't survive security checks — will need security-scoped bookmarks in the manifest instead.

## Current state
v0.4 complete. Click-to-select model, Control+trash, double-click to open. Structure:
- `Bundle.xcodeproj` — Xcode project config
- `Bundle/BundleApp.swift` — app entry point, delegates to AppDelegate
- `Bundle/AppDelegate.swift` — wires ShelfWindowController + HotkeyManager on launch
- `Bundle/ShelfConfig.swift` — config constants (slotCount, sizes, dragHandleHeight) + position persistence
- `Bundle/ShelfWindowController.swift` — owns the NSPanel (show/hide/drag/position save)
- `Bundle/ShelfView.swift` — SwiftUI slot UI; click-to-select, return/trash button, Control key monitor, drag handle
- `Bundle/ShelfStore.swift` — owns slot state ([ShelfEntry?]); file move/return/trash/persistence; single place to swap storage strategy
- `Bundle/FileDragSource.swift` — DragItem struct + AppKit NSDraggingSource + NSFilePromiseProvider; handles click, double-click, and drag-out with 5pt drag threshold
- `Bundle/HotkeyManager.swift` — Carbon RegisterEventHotKey, fires ⌘⌥B
- `Bundle/DragMonitor.swift` — stub for v0.2

## v0.4 — What was built

### Interaction model
- **Hover** — does nothing. No button, no highlight.
- **Single click** — selects that slot. Deselects all others. Blue ring + subtle blue fill appears inside the circle.
- **Click empty slot or empty area** — deselects everything.
- **Selection resets when panel closes** — not persisted.

### Visual: selected state
- Outer ring: system blue (replaces white stroke), lineWidth 2
- Circle fill: `Color.accentColor.opacity(0.2)`
- Return button (↩) appears on selected slot only, not on hover

### Modifier key
- **Control held** → all occupied slots show red trash icon; clicking one sends that file to Trash

### Double-click to open
- Double-click an occupied slot → opens the file in its default app via `NSWorkspace.open()`
- Folders open in Finder; all other types open in their default app

### Drag sensitivity
- 5pt minimum drag threshold before drag session initiates — prevents accidental drags on click

### Deferred to later version
- Command+click multi-select — attempted, not reliable; removed cleanly for future revisit

## Roadmap
- [x] v0.1 — Shelf appears and hides with a global hotkey (⌘⌥B)
- [~] v0.2 — Detect spacebar mid-drag to trigger the shelf (parked — see "What was ruled out")
- [x] v0.3 — Drop files in, drag files out, file icons, return-to-origin, command+trash, persistent storage, drag handle
- [x] v0.4 — Click-to-select, Control+trash, double-click to open, drag sensitivity threshold
- [ ] v0.5 — Polish and animations

## Repo
https://github.com/rawmoz/Bundle
Local: /Users/danielramos/dev/Bundle

## Working style
- User is a vibe coder — AI writes all the code, user runs it in Xcode and reports back
- Keep files small and focused, one feature per file where possible
- User pastes errors from Xcode, Claude fixes them
- Do NOT hard-code values that are meant to be configurable later (slot count, edge position, orientation)
- Update this file at the end of every session
