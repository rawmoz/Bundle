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

## UX decisions
- Shelf floats **anywhere on screen** — position set by the user, not hard-coded
- Panel is **draggable** — user drags the panel itself to reposition it; position saved to UserDefaults immediately on move
- **7 circular slots** stacked vertically (not hard-coded, variable)
- Does **not** persist after restart — shelf clears on quit (position persists, file contents do not)
- Dragging a file out behaves like a **normal system drag**
- **Two distinct triggers** — see Core Interaction above. These are separate mechanisms, not interchangeable.
- **Spacebar mid-drag** — puts a file in. Only fires when macOS is in an active drag state. Never fires on hover, click, or focus.
- **Global hotkey (TBD)** — retrieves a file. Opens the shelf at any time so the user can drag their file back out.
- Minus button **clears slot only**, never deletes the actual file

## Current state
v0.1 complete. Shelf panel appears and hides with ⌘⌥B. Position persists via UserDefaults. Structure:
- `Bundle.xcodeproj` — Xcode project config
- `Bundle/BundleApp.swift` — app entry point, delegates to AppDelegate
- `Bundle/AppDelegate.swift` — wires ShelfWindowController + HotkeyManager on launch
- `Bundle/ShelfConfig.swift` — config constants (slotCount, sizes) + position persistence
- `Bundle/ShelfWindowController.swift` — owns the NSPanel (show/hide/drag/position save)
- `Bundle/ShelfView.swift` — SwiftUI placeholder UI (7 empty circles, frosted panel)
- `Bundle/HotkeyManager.swift` — Carbon RegisterEventHotKey, fires ⌘⌥B
- `Bundle/DragMonitor.swift` — stub for v0.2

## Roadmap
- [x] v0.1 — Shelf appears and hides with a global hotkey (⌘⌥B)
- [ ] v0.2 — Detect spacebar mid-drag to trigger the shelf
- [ ] v0.3 — Drop files in, drag files out, file icons displayed
- [ ] v0.4 — Minus button clears a slot
- [ ] v0.5 — Frosted glass UI, circular slots, left edge anchoring
- [ ] v0.6 — Polish and animations

## Repo
https://github.com/rawmoz/Bundle
Local: /Users/danielramos/dev/Bundle

## Working style
- User is a vibe coder — AI writes all the code, user runs it in Xcode and reports back
- Keep files small and focused, one feature per file where possible
- User pastes errors from Xcode, Claude fixes them
- Do NOT hard-code values that are meant to be configurable later (slot count, edge position, orientation)
- Update this file at the end of every session
