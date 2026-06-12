# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Open

- **Where:** `ContainerAppTests/ContainerCLIRuntimeIntegrationTests.swift` (~line 18, `containerSystemIsAvailable()`)
  **What:** Availability check hardcodes `/usr/local/bin/container`; on machines with the CLI elsewhere (e.g. Homebrew path) the integration suite silently skips even when the system runs.
  **Fix:** Mirror ContainerCLIRuntime's discovery chain (well-known paths + `which`) in the check.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.

- **Where:** `ContainerApp/ViewModels/ContainersViewModel.swift`, `handle(_:)`
  **What:** On `.cliNotFound` / `.systemNotRunning` the handler clears `containers` and `stats` but not `images`, so stale images persist in model state while the system is down. Masked in the UI because `SystemStatusGate` hides the Images section in those states.
  **Fix:** Add `images = []` alongside the existing clears in both branches.

- **Where:** `ContainerApp/ViewModels/ContainersViewModel.swift`, `refreshStats()`
  **What:** Standalone stats refresh doesn't re-run `markInUse`, so image in-use flags could lag container changes if `refreshStats()` were ever used for that. Currently harmless — it's only called for stats and doesn't structurally change `containers`.
  **Fix:** Either fold `refreshStats()` into `refresh(quiet: true)` or append `images = Self.markInUse(images, containers: containers)` at its end.

- **Where:** `ContainerApp/Views/Dashboard/LogsView.swift` (~line 44, two-axis `ScrollView` around a single `Text`)
  **What:** Same Core Animation texture-limit bug that blanked the Raw JSON tab (fixed there via `SelectableMonospacedTextView`): the whole log text draws as one layer, which silently fails past ~16,384 px. Low urgency — logs are capped at 100 lines today — but a chatty container with very long lines could still trigger it.
  **Fix:** Swap the `ScrollView([.horizontal, .vertical]) { Text(...) }` for `SelectableMonospacedTextView(text:)` like `RawJSONView` now does.

- **Where:** `ContainerApp/Utilities/ComposeFileParser.swift` (service-name ordering)
  **What:** Yams' `YAMLDecoder` decodes mappings into Swift `Dictionary`, losing YAML declaration order, so `ComposeProject.serviceNames` is sorted alphabetically instead of file order. Cosmetic only — affects row order in the services table, not behavior.
  **Fix:** Re-parse with Yams' `Node`-level API (`Yams.compose(yaml:)` exposes ordered `Node.mapping` keys) and use that order for `serviceNames`.

- **Where:** Compose support (Phase 6), tooling constraint
  **What:** `container-compose down` 0.12.0 (current brew formula) is broken against container runtime 1.0.0 — XPC protocol mismatch (`DecodingError.typeMismatch … Path: signal`), the container keeps running. The app therefore implements Down via its own `ContainerRuntime.stop(id:)` on matched containers and never shells out to `container-compose down`.
  **Fix:** When the brew formula ships 1.0.0+, optionally switch Down back to `container-compose down` for dependency-aware stop ordering (re-verify against the runtime first).

- **Where:** Images section (Phase 5), deferred scope
  **What:** Not implemented by design: `image pull`/`push`/`tag`/`save`/`load` UI, `prune --all` (UI prunes dangling only), and visibility of dangling images (the list shows only what `image list` returns). The new `ImagesView`/`ImageDetailPanel` have no snapshot/UI test coverage (decoder, in-use, and runtime layers are tested).
  **Fix:** See "Open questions / future ideas" in `plans/phase-5-images.md` when picking these up.

- **Where:** Compose support (Phase 6), deferred feature
  **What:** Log streaming is not implemented. Up always runs detached (`-d`); per-container live logs would require a streaming `ProcessRunner` API. The better long-term shape is `container logs --follow` per container, which would benefit all containers, not just compose-managed ones.
  **Fix:** Add a streaming variant to `ProcessRunning` / `ProcessRunner`, then wire `container logs --follow` into a live log view. Compose log streaming can follow from there.

- **Where:** `ContainerApp/ViewModels/ContainersViewModel.swift`, compose status derivation
  **What:** Two registered compose projects whose folder names resolve to the same project name (e.g. `~/a/myapp/compose.yml` and `~/b/myapp/compose.yml`) collide on container ids (`myapp-web`, etc.). The app has no detection or warning for this case; both projects will claim the same running containers.
  **Fix:** After reparsing projects on refresh, detect duplicate `projectName` values and surface a warning row (e.g. `isMissing`-style indicator) in the project list.

- **Where:** `ContainerApp/Views/Dashboard/ComposeProjectsView.swift`, `ComposeProjectDetailPanel.swift`
  **What:** No UI or snapshot test coverage for `ComposeProjectsView` or `ComposeProjectDetailPanel`. The parser, store, and status-derivation layers are unit-tested, but the view layer is not.
  **Fix:** Add preview-based snapshot tests or UI tests once a snapshot-testing dependency is chosen for the project.

- **Where:** `ContainerApp/ViewModels/ContainersViewModel.swift`, compose Down ordering
  **What:** App-side Down (project and per-service) stops containers via `ContainerRuntime.stop(id:)` in reverse `serviceNames` order. Because `serviceNames` is sorted alphabetically (YAML order is lost — see ordering issue above), stop order is alphabetical-reversed, not YAML-reversed. It also does not consider `depends_on` dependents the way `container-compose down` would.
  **Fix:** Resolve the YAML ordering issue first (Node-level API), then the stop order will match reverse file order. For `depends_on`-aware ordering, a topological sort over the dependency graph would be needed.
