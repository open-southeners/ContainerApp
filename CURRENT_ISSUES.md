# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Open

- **Where:** `ContainerBarTests/ContainerCLIRuntimeIntegrationTests.swift` (~line 18, `containerSystemIsAvailable()`)
  **What:** Availability check hardcodes `/usr/local/bin/container`; on machines with the CLI elsewhere (e.g. Homebrew path) the integration suite silently skips even when the system runs.
  **Fix:** Mirror ContainerCLIRuntime's discovery chain (well-known paths + `which`) in the check.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.

- **Where:** `ContainerBar/ViewModels/ContainersViewModel.swift`, `handle(_:)`
  **What:** On `.cliNotFound` / `.systemNotRunning` the handler clears `containers` and `stats` but not `images`, so stale images persist in model state while the system is down. Masked in the UI because `SystemStatusGate` hides the Images section in those states.
  **Fix:** Add `images = []` alongside the existing clears in both branches.

- **Where:** `ContainerBar/ViewModels/ContainersViewModel.swift`, `refreshStats()`
  **What:** Standalone stats refresh doesn't re-run `markInUse`, so image in-use flags could lag container changes if `refreshStats()` were ever used for that. Currently harmless — it's only called for stats and doesn't structurally change `containers`.
  **Fix:** Either fold `refreshStats()` into `refresh(quiet: true)` or append `images = Self.markInUse(images, containers: containers)` at its end.

- **Where:** `ContainerBar/Views/Dashboard/LogsView.swift` (~line 44, two-axis `ScrollView` around a single `Text`)
  **What:** Same Core Animation texture-limit bug that blanked the Raw JSON tab (fixed there via `SelectableMonospacedTextView`): the whole log text draws as one layer, which silently fails past ~16,384 px. Low urgency — logs are capped at 100 lines today — but a chatty container with very long lines could still trigger it.
  **Fix:** Swap the `ScrollView([.horizontal, .vertical]) { Text(...) }` for `SelectableMonospacedTextView(text:)` like `RawJSONView` now does.

- **Where:** Images section (Phase 5), deferred scope
  **What:** Not implemented by design: `image pull`/`push`/`tag`/`save`/`load` UI, `prune --all` (UI prunes dangling only), and visibility of dangling images (the list shows only what `image list` returns). The new `ImagesView`/`ImageDetailPanel` have no snapshot/UI test coverage (decoder, in-use, and runtime layers are tested).
  **Fix:** See "Open questions / future ideas" in `plans/phase-5-images.md` when picking these up.
