# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-06-13

### Added

- Compose projects section for registering Docker Compose files, persisting them across launches, viewing per-service state, and running project or service Up, Down, and Build actions.
- Compose project detail panel with service images, container states, action output, and a shortcut to open matching containers in the main dashboard.
- `container-compose` runtime integration with independent binary discovery, a configurable path in Settings, an installation prompt when unavailable, and mock runtime support.
- Compose YAML parsing via Yams, including declaration-order preservation, null service bodies, `depends_on` array and map forms, explicit `container_name` values, and dependency-aware project stop ordering.
- Duplicate Compose project-name detection with an explanatory warning for container identifier collisions.
- Live Compose command output while images are pulled or built, with ANSI and carriage-return progress formatting cleaned for display.
- Homebrew installation instructions for the Open Southeners tap and `container-app` cask.
- Compose parser, project store, status matching, action error, duplicate-name, runtime, and live-progress test coverage.

### Fixed

- Compose services now match containers using explicit `container_name` values when present, fixing projects that remained at `0 of N running` despite their containers running.
- Compose Down actions now stop containers using their resolved custom names and project dependency order.
- Compose action failures remain visible after refresh and include useful command output instead of being hidden by macOS system logging noise.
- Compose progress output is shown before the command finishes instead of appearing only after long image downloads or builds complete.
- Compose services retain their YAML declaration order, and `depends_on` values are parsed without rejecting mixed map value types.
- Container lists, image state, and Compose status refresh correctly after actions; stale image state is cleared when the container system is unavailable.
- Logs use the native selectable monospaced text view, preventing long output from disappearing at Core Animation texture limits.
- Integration tests discover the Apple `container` binary through standard paths and `which` instead of assuming `/usr/local/bin/container`.

### Changed

- `ProcessRunner` now supports working directories and incremental stdout/stderr callbacks while retaining complete buffered command results.
- Binary discovery caching is shared through `BinaryCache`, and Compose actions use a common asynchronous action scaffold for busy state, refresh ordering, output, and error handling.
- Settings path override controls are shared between the Apple `container` and `container-compose` CLIs.
- Compose Down uses the Apple `container stop` command because `container-compose down` 0.12.0 is incompatible with Apple container runtime 1.0.0.

## [1.2.0] - 2026-06-12

### Changed

- Project renamed from ContainerBar to ContainerApp: source directories, Xcode targets, scheme, bundle identifiers, and all documentation updated accordingly.

## [1.1.0] - 2026-06-11

### Added

- Images section in the dashboard sidebar: sortable table with Name, Architecture, Size, and In-Use columns; per-image detail panel with raw JSON inspect; individual delete and Prune Images (dangling only) actions. Size is summed across `variants[]` — manifest descriptor size is excluded.
- In-use detection for images: cross-references running containers' `imageReference` field against the fully-qualified image name.
- `Start` container action added to the detail panel header, menu bar row, and context menu — shown in place of Stop for stopped containers; Kill and Shell remain disabled when the container is not running.
- Right-click context menu on container table rows. Single-row: Logs, Shell (disabled when stopped), Inspect, divider, Start/Stop (state-dependent), Kill (disabled when stopped), Delete. Multi-row: Kill Selected (disabled when none are running), Delete Selected.
- Automatic log polling in the Logs detail tab: loads on tab activation and refreshes every 2 s in quiet mode (no loading indicator). Cancels and clears when the selected container changes.
- App icon and custom menu bar icon (vector PDF); falls back to a correctly sized SF Symbol template image when the custom asset is unavailable.
- Hover highlight on menu bar container rows using the system selection colour.
- App window activation when opening a container from the menu bar.
- Reusable build workflow in CI; compiled `.app` artifact attached to each release.
- MIT license and Apple `container` runtime acknowledgement.

### Fixed

- Dashboard split panes now fill the full available width via `GeometryReader`; previously floated narrow when no container was selected.
- Name and Image columns in the container and image tables stretch to absorb remaining horizontal space.
- Raw JSON in Inspect tabs rendered via `NSTextView` (via `SelectableMonospacedTextView`) to handle large payloads that caused SwiftUI layout freezes.
- Menu bar icon rendered at the correct point size as a template image; no longer oversized or missing colour inversion in dark menu bars.

### Changed

- Stale logs and inspect text are cleared immediately when the selected container changes, preventing a flash of the previous container's data.
- `SystemStatusGate`, `RawJSONView`, and table-sizing logic extracted into shared components reused across the Containers and Images sections.

## [1.0.0] - 2026-06-11

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

[1.3.0]: https://github.com/OpenSoutheners/AppleContainerUI/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/OpenSoutheners/AppleContainerUI/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/OpenSoutheners/AppleContainerUI/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/OpenSoutheners/AppleContainerUI/releases/tag/v1.0.0
