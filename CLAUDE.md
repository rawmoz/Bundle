# Bundle — Claude Context

## What this is
A macOS utility that gives users a temporary shelf for files mid-workflow. The user grabs a file, hits spacebar while dragging, a frosted glass panel slides in from the left edge of the screen, they drop the file into a circular slot, and retrieve it later via a global hotkey.

Think of it as a physical desk — a neutral staging area with no permanence implied. Not a folder, not a clipboard.

## Core interaction
1. User starts dragging a file or folder
2. Hits spacebar mid-drag → shelf slides in from the left edge of the screen
3. User drops file into one of the circular slots
4. Shelf minimizes out of the way
5. Global hotkey anytime → shelf reopens
6. User drags file back out (behaves exactly like a normal system drag)

## Visual design
- **Panel** — frosted glass (SwiftUI material), anchored to the left edge of the screen
- **Slots** — 7 circular slots stacked vertically. Always visible. Empty slots show as faint empty circles.
- **File icon** — uses macOS native file icon via NSWorkspace (one line, auto-detects file type, shows real icon)
- **Minus button** — appears on each occupied slot, clears that file from the shelf (does NOT delete the file)
- **Future** — horizontal orientation toggle, customizable slot count, customizable edge (left/right). Build slots as a grid component so orientation is just a variable, not a rewrite.

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

## UX decisions
- Shelf anchored to **left edge of screen**
- **7 circular slots** stacked vertically (not hard-coded, variable)
- Does **not** persist after restart — shelf clears on quit
- Dragging a file out behaves like a **normal system drag**
- **Spacebar mid-drag** triggers the shelf
- **Global hotkey** (TBD) opens/closes the shelf anytime
- Minus button **clears slot only**, never deletes the actual file

## Current state
Xcode project scaffolded and builds clean. No functional code yet. Structure:
- `Bundle.xcodeproj` — Xcode project config
- `Bundle/BundleApp.swift` — app entry point
- `Bundle/ContentView.swift` — main UI (currently blank default)

## Roadmap
- [ ] v0.1 — Shelf appears and hides with a global hotkey
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
