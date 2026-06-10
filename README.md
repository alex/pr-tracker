# PR Tracker

A small native macOS app for tracking your own open pull requests, built per the
design spec in "PR Tracker - Design Spec" (Grouped Inbox direction). Three
operations: add a PR by pasting its URL, see all PRs grouped by what they're
waiting on, and mark one PR as depending on another.

Built with SwiftUI via Swift Package Manager — no Xcode project required.

## Requirements

- macOS 14+
- Swift toolchain (Command Line Tools are enough)
- [`gh`](https://cli.github.com) CLI, authenticated (`gh auth login`) — the app
  uses `gh auth token` for GitHub API access

## Build & run

```sh
./build.sh
open "build/PR Tracker.app"
```

(`swift run` also works for quick iteration, without the app bundle niceties.)

## Usage

- **Add a PR** — copy a PR link on GitHub, then press ⌘V anywhere in the app
  (or click the paste field). A popover previews the fetched PR; one click adds
  it to the right group.
- **Groups** — every PR lands in exactly one derived state: Waiting on you
  (changes requested, unresolved comments, failing checks, or draft), Waiting
  on review, Waiting on CI, Blocked (user-set dependency), or Merged. The
  sidebar filters by group or by repository.
- **Dependencies** — right-click a PR → "Blocked by" → pick another tracked PR.
  The blocked PR nests under its blocker with a connector; when the blocker
  merges it returns to its derived state automatically. Cycles are disabled at
  pick time.
- **Other row actions** — double-click (or right-click) to open on GitHub,
  Copy URL, Mark as Merged, Remove from Tracker.
- **Refresh** — every tracked PR is re-fetched every 5 minutes, on app
  activation, via the toolbar refresh button, or with ⌘R. States are always
  derived, never hand-set (except dependency, mark-as-merged, and remove).
- Merged/closed PRs are kept for reference for 3 days, then pruned.

## App icon

`Resources/AppIcon.icns` is generated on first build by
`Tools/make-icon.swift` (headless AppKit drawing + `iconutil`). Delete the
`.icns` and rebuild to regenerate it.

## Data

Tracked PRs persist to
`~/Library/Application Support/PRTracker/prs.json`.

## Debug

`PRTRACKER_SNAPSHOT=/tmp/shot.png` writes a PNG of the app's windows a few
seconds after launch (no screen-recording permission needed);
`PRTRACKER_LIGHT=1` forces light appearance; `PRTRACKER_PASTE=<url>` simulates
the paste-to-add flow. Useful for headless UI verification.
