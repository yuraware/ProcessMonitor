# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

ProcessMonitor is a macOS menu bar app, written in Swift, for discovering and controlling processes.
It is a Swift Package with no Xcode project. The `.app` bundle is assembled by a script.

- Minimum macOS: 13.0. Swift tools version 5.9. Builds with Xcode 26 / Swift 6 toolchains.
- No third-party dependencies.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CProcessInfo/` | C shim over `sysctl` and `libproc` for listing processes and reading resource usage. |
| `Sources/ProcessMonitor/ProcessMonitorApp.swift` | Entry point, plus the `--dump`, `--quit` and `--force-quit` diagnostic flags. |
| `Sources/ProcessMonitor/AppDelegate.swift` | Status item, floating panel, Settings and Welcome windows. |
| `Sources/ProcessMonitor/ProcessSampler.swift` | Samples processes and computes CPU %, memory and energy. |
| `Sources/ProcessMonitor/ProcessListModel.swift` | Observable table state, sampling timer, checked rows and quit flow. |
| `Sources/ProcessMonitor/ProcessTerminator.swift` | Quits processes strictly one at a time. |
| `Sources/ProcessMonitor/ProcessListView.swift` | SwiftUI table and footer. |
| `Sources/ProcessMonitor/SettingsView.swift` | Settings and first-launch Welcome views. |
| `Sources/ProcessMonitor/AppSettings.swift` | `UserDefaults` settings and `SMAppService` launch at login. |
| `Support/Info.plist` | Bundle metadata. `LSUIElement` hides the Dock icon. Holds the version. |
| `scripts/` | `build.sh`, `lint.sh`, `make-icon.sh`. |
| `appcast.xml` | Sparkle-compatible update feed. |

## Commands

```bash
swift build                      # debug compile
scripts/build.sh                 # release build -> dist/ProcessMonitor.app (ad-hoc signed)
scripts/build.sh --install       # also copy to /Applications and launch
scripts/build.sh --dmg           # also create dist/ProcessMonitor-<version>.dmg
scripts/lint.sh                  # swiftformat --lint + swiftlint --strict (must pass)
scripts/lint.sh --fix            # auto-format and auto-correct
.build/release/ProcessMonitor --dump            # print the busiest processes, no UI
.build/release/ProcessMonitor --quit <pid>...   # quit pids sequentially, no UI
```

## Rules

- **Do not sample while hidden.** The panel's visibility drives `ProcessListModel.start()` and `stop()`. Never add background timers that run while the panel is closed.
- **Quit sequentially.** All quitting goes through `ProcessTerminator`, which waits for each process to exit before signalling the next one.
- **Public APIs only.** No private frameworks and no entitlements that require root. GPU % stays "—" until a public source exists.
- **Launch at login uses `SMAppService.mainApp`.** It only works from a real `.app` bundle, not from `swift run`.
- Run `scripts/lint.sh` and `scripts/build.sh` before finishing a change. Both must succeed.
- Keep `CHANGELOG.md` updated under `[Unreleased]` for user-visible changes.

## Releasing

1. Bump `CFBundleShortVersionString` in `Support/Info.plist`.
2. Move `[Unreleased]` entries in `CHANGELOG.md` under the new version.
3. Run `scripts/build.sh --dmg` and upload the DMG to a GitHub release tagged `v<version>`.
4. Add an `<item>` to the top of `appcast.xml` with the DMG byte length.
