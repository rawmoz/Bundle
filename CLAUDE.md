# Bundle — Claude Context

## What this is
A macOS overlay utility that lets users create named Bundles — floating panels that live on the desktop. Each Bundle contains Cells (circular slots) that hold files, folders, images, or plain text. Press `⌘⌥B` to show or hide all bundles.

## Core concepts

**Bundle**
A named floating panel. Multiple bundles can exist simultaneously, each freely positioned anywhere on the desktop. Position is saved and restored on launch.

**Cell**
An empty container — like an unoccupied lot. One-click selects it (turns blue). Once selected, the user fills it by pasting (`⌘V`), dragging content in, or using right-click → Paste. Once occupied it shows a thumbnail and the item's name underneath.

## Creating a Bundle
1. Click "Add new bundle"
2. Enter a custom name (e.g. "School Stuff")
3. Pick a size via the Table Grid picker (visual grid of rows/columns)
4. Bundle appears on screen, ready to use

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
| File (PDF, doc, etc.) | Native macOS file icon (NSWorkspace) | Filename |
| Folder | Native macOS folder icon (NSWorkspace) | Folder name |
| Image (PNG, JPG, etc.) | Actual image preview | Filename |
| Plain text | Text document icon | First ~25 characters of content |

## Storage model
Bundles and their cells are stored locally in the app's Application Support folder. Each Bundle is a directory. Each cell's content lives as a file inside that directory (files, folders, and images are moved in; plain text is saved as a `.txt` file). A `manifest.json` per Bundle tracks cell order, names, and metadata. If the app crashes, all content is safe on disk.

## Positioning
Free positioning — bundles float anywhere on screen. User drags via the `:::` handle to reposition. Position persists per bundle via UserDefaults and is restored on next launch.

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer
- **AppKit** — window management, floating panels
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

## Roadmap
- [ ] TBD — full design being finalized

## Repo
Local: /Users/danielramos/dev/Bundle
Remote: https://github.com/rawmoz/Bundle
