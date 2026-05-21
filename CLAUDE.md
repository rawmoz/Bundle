# Bundle — Claude Context

## What this is
A macOS utility that gives users a temporary shelf for files mid-workflow. The user grabs a file, hits spacebar while dragging, a shelf panel slides in from the side of the screen, they drop the file in, and retrieve it later via a global hotkey.

Think of it as a physical desk — a neutral staging area with no permanence implied. Not a folder, not a clipboard.

## Core interaction
1. User starts dragging a file or folder
2. Hits spacebar mid-drag → shelf slides in from the side of the screen
3. User drops file onto the shelf
4. Shelf minimizes out of the way
5. Global hotkey anytime → shelf reopens
6. User drags file back out (behaves exactly like a normal drag)

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer, declarative
- **AppKit** — window management, floating panel
- **macOS Accessibility APIs** — detecting spacebar keypress during an active system drag from another app (e.g. Finder)
- **Xcode** — IDE, build tool
- **GitHub** — version control, public repo

## What was ruled out and why
- **Electron** — cannot detect spacebar pressed while a file is being dragged in another app (Finder). Requires OS-level access Electron doesn't have. Would have forced a degraded UX (open shelf first, then drag in — breaks the flow).
- **Shake gesture while dragging** — too easy to trigger accidentally, would get annoying fast.
- **Menu bar app** — user didn't want this format.
- **React Native / Tauri** — unnecessary complexity, wrong tool for native Mac utility.

## UX decisions
- Shelf lives anchored to the **side of the screen** (left or right, customizable later)
- Holds up to **~6-7 files** at a time
- Does **not** persist after restart — shelf clears on quit
- Dragging a file out of the shelf behaves like a **normal system drag**, no special interaction
- **Spacebar mid-drag** opens the shelf
- **Global hotkey** (TBD) opens/closes the shelf anytime

## Roadmap
- [ ] v0.1 — Shelf window appears/hides with a global hotkey
- [ ] v0.2 — Detect spacebar mid-drag to trigger the shelf
- [ ] v0.3 — Drop files in, drag files out
- [ ] v0.4 — Hold up to 6 files at a time
- [ ] v0.5 — Shelf anchors to the side of the screen
- [ ] v0.6 — UI polish and animations

## Repo
https://github.com/rawmoz/Bundle
Local: /Users/danielramos/dev/Bundle

## Working style
- User wants to vibe code — AI writes all the code, user runs it in Xcode and reports back
- Keep files small and focused, one feature per file where possible
- User pastes errors from Xcode, Claude fixes them
- Update this file at the end of each session
