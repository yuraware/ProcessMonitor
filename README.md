# ProcessMonitor

[![CI](https://github.com/yuraware/ProcessMonitor/actions/workflows/ci.yml/badge.svg)](https://github.com/yuraware/ProcessMonitor/actions/workflows/ci.yml)

Discover and control processes on Mac.

ProcessMonitor lives in your menu bar. Click its CPU icon to open an Activity Monitor–style table of every running process, with CPU, GPU, memory and energy usage, PID and owner. Tick the processes you want gone and quit or force quit them, one at a time.

It samples processes only while the panel is open, so it uses no CPU in the background.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later, or the Swift command line tools, to build from source

## Download

Grab `ProcessMonitor-<version>.dmg` from the [latest release](https://github.com/yuraware/ProcessMonitor/releases/latest), open it and drag ProcessMonitor to Applications.

Every push to `main` also produces a build. Open the [CI workflow](https://github.com/yuraware/ProcessMonitor/actions/workflows/ci.yml), pick a run and download the `.app` zip or DMG from its Artifacts section.

The app is signed ad hoc, not notarized. On first launch macOS may refuse to open it. Right-click the app, choose Open and confirm, or run:

```bash
xattr -d com.apple.quarantine /Applications/ProcessMonitor.app
```

## Build and install

```bash
git clone https://github.com/yuraware/ProcessMonitor.git
cd ProcessMonitor
scripts/build.sh --install
```

This builds a release binary, bundles it as `ProcessMonitor.app`, signs it ad hoc, copies it to `/Applications` and launches it.

Other options:

```bash
scripts/build.sh          # build dist/ProcessMonitor.app only
scripts/build.sh --run    # build and launch from dist/
scripts/build.sh --dmg    # also create dist/ProcessMonitor-<version>.dmg
scripts/build.sh --clean  # remove previous build output first
```

## Usage

- **Left-click** the menu bar icon to open or close the process panel.
- **Right-click** it for Settings and Quit.
- **Tick checkboxes** to choose processes, then press **Quit** or **Force Quit**.
- **Click ▸** next to an app to expand its child processes. A collapsed row shows the group's combined usage, and ticking it selects the whole group. The header button switches grouping off.
- **Search** by name, PID, user or path. Click a column header to sort.
- **Settings** has "Launch at login" and the refresh interval.

## Development

```bash
brew install swiftformat swiftlint
scripts/lint.sh         # check
scripts/lint.sh --fix   # auto-fix
```

See [AGENTS.md](AGENTS.md) for architecture notes and [CHANGELOG.md](CHANGELOG.md) for release history.

## Limitations

- % GPU shows "—". macOS has no public per-process GPU API.
- Energy is an estimate from CPU time and wake-ups.
- Processes owned by root or other users show limited data and need admin rights to quit.

## License

MIT
