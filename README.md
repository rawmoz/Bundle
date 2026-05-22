# Bundle

A macOS utility that gives you a place to set files down while you work.

Drag a file, hit spacebar, drop it into Bundle. Come back later, grab it out. That's it.

## How it works

1. Start dragging any file or folder
2. Hit spacebar — Bundle slides in from the left edge of your screen
3. Drop the file into one of the slots
4. Hit the global hotkey anytime to open Bundle and drag your file back out

## Design

A frosted glass panel anchored to the left edge of the screen. Seven circular slots stacked vertically — always visible, always in the same place. Drop a file in and its icon appears. Hit the minus button on a slot to clear it.

Files are not deleted when removed from Bundle. The shelf does not persist between sessions.

## Roadmap

- [ ] v0.1 — Shelf appears and hides with a global hotkey
- [ ] v0.2 — Detect spacebar mid-drag to trigger the shelf
- [ ] v0.3 — Drop files in, drag files out, file icons displayed
- [ ] v0.4 — Minus button clears a slot
- [ ] v0.5 — Frosted glass UI, circular slots, left edge anchoring
- [ ] v0.6 — Polish and animations

## Built with

- Swift
- SwiftUI
- macOS Accessibility APIs
