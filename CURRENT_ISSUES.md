# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Phase 0 (2026-06-10)

- **Where:** `ContainerBar/Resources/Info.plist` line 24 (`NSHumanReadableCopyright`)
  **What:** Copyright string is `$(PRODUCT_NAME)`, so the built bundle shows just "ContainerBar" as the copyright.
  **Fix:** Set a real notice, e.g. "Copyright © 2026 Open Southeners", in the plist or via an `INFOPLIST_KEY`/project.yml setting.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.
