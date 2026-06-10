# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Phase 0 (2026-06-10)

- **Where:** `ContainerBar/Resources/Info.plist` line 24 (`NSHumanReadableCopyright`)
  **What:** Copyright string is `$(PRODUCT_NAME)`, so the built bundle shows just "ContainerBar" as the copyright.
  **Fix:** Set a real notice, e.g. "Copyright © 2026 Open Southeners", in the plist or via an `INFOPLIST_KEY`/project.yml setting.

## Phase 1 (2026-06-10)

- **Where:** `ContainerBar/Views/Dashboard/ContainerContentView.swift` (`stateColor(_:)`) and `ContainerBar/Views/Dashboard/ContainerDetailPanel.swift` (`stateColor(_:)`)
  **What:** Identical state→Color mapping duplicated in two views.
  **Fix:** Promote to a `color` property on `ContainerState` in `ContainerBar/Models/ContainerState.swift` and delete both private helpers.

- **Where:** `ContainerBar/Models/ContainerSystemStatus.swift:1`
  **What:** Views compare `model.systemStatus == .running`, relying on Equatable implied via Hashable.
  **Fix:** Declare `Equatable` explicitly on the enum for clarity/robustness.

- **Where:** `ContainerBar/ViewModels/ContainersViewModel.swift` (~line 88, `filteredContainers`)
  **What:** Returns all containers for `.images`/`.settings` sidebar sections; harmless today because `ContainerContentView` never renders the table for those sections, but surprising as API.
  **Fix:** Return `[]` (or restructure) when those sections gain real content in Phase 4.

- **Where:** `ContainerBar/Views/Dashboard/ContainerContentView.swift` (`containerListContent` helper)
  **What:** Uses a local `@Bindable var model = model` inside a ViewBuilder function — works, but an unusual pattern that may be fragile across Swift versions.
  **Fix:** Inline into `body` or pass explicit Bindings if it ever misbehaves.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.
