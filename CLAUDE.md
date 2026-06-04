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

## Bundle header (`:::` handle)
- **Hold + drag** — moves the bundle anywhere on the desktop, position saves automatically
- **Click** — opens the bundle settings popover:
  1. Rename
  2. Change Bundle size (re-opens the Table Grid picker)
  3. Delete

## Cell interaction model

**One-click**
Selects the cell (blue ring). A selected cell can:
- Receive a paste (`⌘V`) — file, folder, image, or plain text from clipboard
- Receive a drag — drag any content directly into the cell
- Be copied from — `⌘C` copies the cell's content back to clipboard

**Right-click on empty cell**
- Paste

**Right-click on occupied cell**
- Delete content
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
One master folder lives at `~/Library/Application Support/Bundle/Bundles/`. Each BundlePanel gets its own subdirectory named by UUID. Files and folders dropped into a cell are **moved** (not copied) into that bundle's directory. Plain text is saved as a `.txt` file. A `manifest.json` per bundle tracks cell positions, display names, and metadata. If the app crashes, all content is safe on disk.

```
~/Library/Application Support/Bundle/
  Bundles/
    [bundle-uuid]/
      manifest.json
      [cell content files and folders]
    [bundle-uuid]/
      manifest.json
      [cell content files and folders]
```

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
`NSPanel` with `.borderless + .nonactivatingPanel` style mask. Size calculated explicitly: `padding(16) + columns * cellSize(64) + (columns-1) * gap(12) + padding(16)`. Cell size 64pt matches macOS Control Center small widget size.

### v0.1 coordinator
`AppCoordinator` is a temporary `@Observable` class stored as `@State` in `BundleApp`. It owns `[BundlePanelController]` and `HotkeyManager` for v0.1 only. In v0.2 it is deleted and replaced by `BundleManager`.

## Roadmap
See `ROADMAP.md` for the full versioned build plan.

## Repo
Local: /Users/danielramos/dev/Bundle
Remote: https://github.com/rawmoz/Bundle
