# Bundle

A macOS utility that gives you a place to set files down while you work.

Drop a file into Bundle. Come back later, drag it back out. That's it.

## How it works

**Putting a file in:**
1. Hit ⌘⌥B — Bundle's panel appears
2. Drag any file or folder from Finder into one of the circular slots
3. The file moves into Bundle's storage — its icon appears in the slot

**Getting a file back out:**
4. Hit ⌘⌥B again — panel opens
5. Drag the file back out into wherever you need it
6. Or hover a slot and click the return button (↩) to send it back to where it came from

**Clearing a slot:**
- Hover a slot → click ↩ to return the file to its original location
- Hold ⌘ while the panel is open → slots show a red trash icon to delete instead

## Design

A frosted glass panel that floats anywhere on screen. Drag the grip handle at the top to reposition it — Bundle remembers that position next time.

Seven circular slots stacked vertically. Drop a file in and its real macOS icon appears. Files persist between sessions — if you quit and relaunch, your shelf is still there.

## Roadmap

- [x] v0.1 — Shelf appears and hides with a global hotkey (⌘⌥B)
- [~] v0.2 — Detect spacebar mid-drag to trigger the shelf (parked — macOS Sequoia limitation)
- [x] v0.3 — Drop files in, drag files out, file icons, return-to-origin, persistent storage
- [ ] v0.4 — Click to select, multi-select (⌘+click), batch return/trash, multi-file drag, double-click to open
- [ ] v0.5 — Polish and animations

## Built with

- Swift + SwiftUI
- AppKit
- macOS Accessibility APIs
