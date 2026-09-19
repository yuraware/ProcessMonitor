# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Processes are grouped with their child processes under one collapsible row. A collapsed group shows the
  combined CPU, memory and energy of the whole group and sorts by those totals; click ▸ to expand it and see
  each member. Checking a group checks every member, so a whole app can be quit in one go.
- "Expand", "Collapse", "Expand All" and "Collapse All" in the table's context menu.
- Toggle in the panel header and in Settings to switch grouping off. Searching always shows a flat list.
- GitHub Actions workflow that lints and builds on every push and pull request, publishes the `.app` and DMG as workflow artifacts, and attaches the DMG to the GitHub release for `v*` tags.

### Fixed
- Clicking the menu bar icon while the panel was open reopened it instead of hiding it.
- Changing the refresh interval in Settings applied the previous value instead of the newly chosen one.

## [0.0.1] - 2026-09-15

### Added
- Menu bar–only app (no Dock icon) that opens a floating panel from the status bar icon.
- Activity Monitor–style process table with Process Name, % CPU, % GPU, Memory, Energy, PID and User columns.
- Sorting by any column and search by name, PID, user or executable path.
- Checkbox column to pick processes, with Quit, Force Quit and Uncheck All actions.
- Sequential quitting: each checked process is signalled and must exit before the next one is quit.
- Welcome screen on first launch explaining the app and offering "Launch at login".
- Settings window with "Launch at login", refresh interval and app description.
- Sampling runs only while the panel is visible, so the app uses no CPU when closed.
- `scripts/build.sh` to build, sign ad hoc, install and package a DMG locally.
- SwiftFormat and SwiftLint configuration with `scripts/lint.sh`.
- Sparkle-compatible `appcast.xml` update feed.

### Known limitations
- % GPU shows "—" because macOS has no public per-process GPU API.
- Energy is an estimate based on CPU time and idle wake-ups, not Apple's exact Energy Impact formula.
- Processes owned by other users or root show no CPU, memory or energy data and cannot be quit without admin rights.

[Unreleased]: https://github.com/yuraware/ProcessMonitor/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/yuraware/ProcessMonitor/releases/tag/v0.0.1
