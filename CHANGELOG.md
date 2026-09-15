# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
