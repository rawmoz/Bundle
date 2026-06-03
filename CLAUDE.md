# Bundle — Claude Context

## What this is
A macOS overlay utility that lets users create named Bundles — floating panels that live on the desktop. Each Bundle contains Cells (circular slots) that hold files, folders, or plain text. Press `⌘⌥B` to show or hide all bundles.

## Core concepts

**Bundle**
A named floating panel. Multiple bundles can exist simultaneously, each freely positioned anywhere on the desktop. Position is saved and restored on launch.

**Cell**
A circular slot inside a Bundle that holds one item. Clicking a cell selects it (blue ring). A selected empty cell accepts a paste (`⌘V`) — file, folder, or plain text.

Each cell holds one of three things:
- **File** (PDF, image, etc.) — thumbnail is the native macOS file icon via NSWorkspace
- **Folder** — thumbnail is the native macOS folder icon via NSWorkspace
- **Plain text** — stored as a `.txt` file, thumbnail shows a text icon, name shows first line of content

## Storage model
Bundles and their cells are stored locally in the app's Application Support folder. Each Bundle is a directory. Each cell's content lives as a file inside that directory (files and folders are moved in; plain text is saved as `.txt`). A `manifest.json` per Bundle tracks cell order, names, and metadata. If the app crashes, all content is safe on disk.

## Positioning
Free positioning — bundles float anywhere on screen. User drags to reposition. Position persists via UserDefaults per bundle and is restored on next launch. Works across multiple displays without special handling.

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer
- **AppKit** — window management, floating panels
- **NSWorkspace** — native file icons
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
