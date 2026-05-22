# Bundle

A macOS utility that gives you a place to set files down while you work.

Drag a file, hit spacebar, drop it into Bundle. Come back later, grab it out. That's it.

## How it works

**Putting a file in:**
1. Start dragging any file or folder in Finder
2. Hit spacebar while still dragging — Bundle's panel appears
3. Drop the file into one of the circular slots — panel hides

**Getting a file back out:**
4. Hit the global hotkey (TBD) — Bundle's panel opens
5. Drag the file back out into wherever you need it

These are two distinct triggers for two distinct moments. Spacebar only works mid-drag. The global hotkey works anytime.

## Design

A frosted glass panel that floats anywhere on screen. Drag the panel itself to place it wherever feels natural — Bundle remembers that position next time.

Seven circular slots stacked vertically. Drop a file in and its icon appears. Hit the minus button on a slot to clear it (the file is never deleted, just removed from the shelf).

File contents don't persist between sessions. Panel position does.

## Roadmap

- [ ] v0.1 — Shelf appears and hides with a global hotkey
- [ ] v0.2 — Detect spacebar mid-drag to trigger the shelf
- [ ] v0.3 — Drop files in, drag files out, file icons displayed
- [ ] v0.4 — Minus button clears a slot
- [ ] v0.5 — Frosted glass UI, circular slots, draggable panel with persistent position
- [ ] v0.6 — Polish and animations

## Built with

- Swift
- SwiftUI
- macOS Accessibility APIs
