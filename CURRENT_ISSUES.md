# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Open

- **Where:** Compose Up failures on the reporting machine (runtime behavior, not yet reproduced with visible errors)
  **What:** The original user report (2026-06-12) — Up on a registered project ticks busy then nothing runs — was caused by *two* layers. The error-visibility layer is fixed (see Resolved): failures now surface in the error banner and the detail panel's Last Output shows the CLI stderr. The *underlying* `container-compose up` failure on that machine is still undiagnosed because it was invisible at the time.
  **Fix:** Re-run the failing scenario on the affected machine with the fixed build; the banner/Last Output will now show the CLI error. First candidates: GUI-spawned environment differences, or a compose file using `build:`-only services.

- **Where:** Compose support (Phase 6), upstream tool constraint — confirmed root cause of the 2026-06-12 user report
  **What:** `container-compose` (all versions incl. latest main) decodes per-service `networks:` and `depends_on:` strictly as string arrays (`Service.swift` uses `[String]`). The Docker-spec *map* forms (`networks: { net: { aliases: [...] } }`, `depends_on: { db: { condition: … } }`) fail its whole-file decode with `DecodingError.typeMismatch: expected … Sequence … found Node` on `up`/`down`/`build`. The app now surfaces this correctly (post noise-filter fix); the app's own parser is deliberately more lenient, so services render fine and the failure only appears on Up. `container_name:` is parsed but ignored by the tool — naming is always `<project>-<service>`, so status matching is unaffected.
  **Fix:** Nothing app-side. User-side: convert affected services to the array form (`networks: [name]`), losing `aliases`. Upstream: candidate issue/PR to Mcrich23/Container-Compose to accept both YAML forms.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.

- **Where:** Compose support (Phase 6), tooling constraint
  **What:** `container-compose down` 0.12.0 (current brew formula) is broken against container runtime 1.0.0 — XPC protocol mismatch (`DecodingError.typeMismatch … Path: signal`), the container keeps running. The app therefore implements Down via its own `ContainerRuntime.stop(id:)` on matched containers and never shells out to `container-compose down`.
  **Fix:** When the brew formula ships 1.0.0+, optionally switch Down back to `container-compose down` (re-verify against the runtime first).

- **Where:** `ContainerApp/ViewModels/ContainersViewModel.swift`, `downService(_:in:)`
  **What:** Per-service Down stops *direct* dependents before the target, but not transitive dependents (dependents-of-dependents keep running against a stopped dependency). Project-level Down is fully dependency-ordered via `ComposeFileParser.stopOrder`.
  **Fix:** Compute the transitive dependent closure (reuse the `stopOrder` graph walk) before stopping a single service.

- **Where:** Images section (Phase 5), deferred scope
  **What:** Not implemented by design: `image pull`/`push`/`tag`/`save`/`load` UI, `prune --all` (UI prunes dangling only), and visibility of dangling images (the list shows only what `image list` returns). The new `ImagesView`/`ImageDetailPanel` have no snapshot/UI test coverage (decoder, in-use, and runtime layers are tested).
  **Fix:** See "Open questions / future ideas" in `plans/phase-5-images.md` when picking these up.

- **Where:** Compose support (Phase 6), deferred feature
  **What:** Log streaming is not implemented. Up always runs detached (`-d`); per-container live logs would require a streaming `ProcessRunner` API. The better long-term shape is `container logs --follow` per container, which would benefit all containers, not just compose-managed ones.
  **Fix:** Add a streaming variant to `ProcessRunning` / `ProcessRunner`, then wire `container logs --follow` into a live log view. Compose log streaming can follow from there.

- **Where:** `ContainerApp/Views/Dashboard/ComposeProjectsView.swift`, `ComposeProjectDetailPanel.swift`
  **What:** No UI or snapshot test coverage for `ComposeProjectsView` or `ComposeProjectDetailPanel`. The parser, store, status-derivation, and action-error layers are unit-tested, but the view layer is not.
  **Fix:** Add preview-based snapshot tests or UI tests once a snapshot-testing dependency is chosen for the project.

## Resolved (2026-06-12, orchestrated fix pass)

- **Compose action errors invisible** — all five compose actions (`upProject`, `buildProject`, `upService`, `downProject`, `downService`) now refresh *before* surfacing the error, so `errorMessage` survives; `.commandFailed` stderr is shown in the detail panel's Last Output. Shared `composeAction` helper replaces the five duplicated Task scaffolds; covered by the `ComposeActionErrorTests` regression suite (mock failure mode added to `MockComposeRuntime`).
- **YAML service order lost** — `ComposeFileParser` now reads service keys in document order via Yams' `Node` API; `serviceNames` matches file order.
- **Down ordering** — `depends_on` is parsed (array and map forms, lenient values), and project Down stops services via `ComposeFileParser.stopOrder` (Kahn's algorithm, cycle-safe, deterministic).
- **Duplicate compose project names** — detected after each reparse (`detectDuplicateProjectNames`); colliding rows show a warning triangle with an explanatory tooltip.
- **Stale `images` on system-down** — `handle(_:)` now clears `images` alongside `containers`/`stats` in the `.cliNotFound`/`.systemNotRunning` branches.
- **`refreshStats()` in-use lag** — re-runs `markInUse` at the end.
- **LogsView texture-limit blanking** — log text now renders via `SelectableMonospacedTextView` (same fix as RawJSONView).
- **Integration-test availability check hardcoded path** — shared `TestSupport.swift` discovery helper (well-known paths + `which`) replaces the hardcoded `/usr/local/bin/container`; integration suites verified running on Homebrew-path machines.
