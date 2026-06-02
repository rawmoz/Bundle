# Bundle — Claude Context

## What this is
A macOS overlay utility that lets users create named Bundles — floating panels on the desktop, each containing Cells (circular slots) that hold files and folders. Press `⌘⌥B` to show or hide all bundles.

## Core concepts
- **Bundle** — a named floating panel. Multiple bundles can exist simultaneously, each positioned independently on the desktop.
- **Cell** — a circular slot inside a Bundle that holds a single file or folder. 

- **Idea** - We will store these locally in the application files. A `Bundle` will be a file and the `cells` will be teh files or folders inside them. So if the application crashes the files should safely still be in the applciaitons folder. 

## Tech stack
- **Swift** — language
- **SwiftUI** — UI layer
- **AppKit** — window management, floating panels
- **NSWorkspace** — native file icons
- **Carbon** — global hotkey registration
- **Xcode** — IDE and build tool
- **GitHub** — version control (`github.com/rawmoz/Bundle`)

## Working style
- User wants to vibe code — Claude writes all code, user runs it in Xcode and reports back
- Keep files small and focused, one feature per file where possible
- User pastes errors from Xcode, Claude fixes them
- Do not hard-code values that are meant to be configurable later
- Update this file at the end of every session

## Roadmap
- [ ] TBD — full design being finalized

## Repo
Local: /Users/danielramos/dev/Bundle
