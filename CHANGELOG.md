# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-10

### Added

- Menu-bar popover showing system status, up to five running containers, and quick Logs / Shell / Stop actions per container.
- Start System and Stop System controls in the menu-bar popover and dashboard toolbar.
- Full dashboard window (`NavigationSplitView`) with an All / Running / Stopped sidebar and a sortable container table (Name, Image, State, CPU, Memory columns).
- Per-container detail panel with Overview, Logs (last 100 lines), Inspect (raw JSON), and Stats tabs.
- Container actions: Stop, Kill, Delete, Prune, and Open Shell (opens Terminal.app via AppleScript).
- Live stats polling every five seconds while the dashboard window is visible; quiet refresh (no loading spinner).
- CPU percentage derived from delta between two `container stats` samples (`cpuUsageUsec`).
- Settings pane with a CLI path override, persisted via `@AppStorage` and invalidating the binary cache on change.
- `ContainerRuntime` protocol with `ContainerCLIRuntime` (real) and `MockContainerRuntime` (canned data for UI work).
- `ProcessRunner` actor wrapping `Foundation.Process`: concurrent stdout/stderr reads to prevent pipe-buffer deadlocks; stdin set to `/dev/null` so interactive CLI prompts fail fast.
- Typed error mapping (`cliNotFound`, `systemNotRunning`, `commandFailed`, `decodingFailed`) — raw stderr is never shown in the UI.
- Binary discovery chain: UserDefaults override → `/usr/local/bin` → `/opt/homebrew/bin` → `which container`; result cached per override string in a `BinaryCache` actor.
- DTO layer (`CLIContainerDTO`, `CLIStatsDTO`) with all-optional fields to tolerate unknown future CLI keys; `FlexibleContainerDecoder` as the sole decode entry point.
- `TerminalLauncher` with injection-safe shell command generation: container id validated against `^[A-Za-z0-9._-]+$` before interpolation.
- Swift Testing test suites: `ContainerCLIModelsTests` (decoder against real fixture output), `StatsMergeTests` (CPU delta logic), `TerminalLauncher` tests, and `ContainerCLIRuntimeIntegrationTests` (skipped when CLI is absent).
- Fixture files in `Fixtures/` capturing real `container list`, `container stats`, `container inspect`, and `container system status` output.
- XcodeGen `project.yml` as the sole source of truth for the Xcode project (`.xcodeproj` is gitignored).
- App Sandbox disabled; `NSAppleEventsUsageDescription` declared for Terminal scripting.

[Unreleased]: https://github.com/OpenSoutheners/AppleContainerUI/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/OpenSoutheners/AppleContainerUI/releases/tag/v1.0.0
