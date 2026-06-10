# Current issues

Discovered during orchestrated work; not blocking, not yet fixed.

## Open

- **Where:** `ContainerBarTests/ContainerCLIRuntimeIntegrationTests.swift` (~line 18, `containerSystemIsAvailable()`)
  **What:** Availability check hardcodes `/usr/local/bin/container`; on machines with the CLI elsewhere (e.g. Homebrew path) the integration suite silently skips even when the system runs.
  **Fix:** Mirror ContainerCLIRuntime's discovery chain (well-known paths + `which`) in the check.

- **Where:** CI / build invocations (no file yet)
  **What:** `xcodebuild` warns "Using the first of multiple matching destinations" (arm64 vs x86_64 vs Any Mac); non-deterministic destination selection.
  **Fix:** Pass `-destination 'platform=macOS,arch=arm64'` in any scripted/CI build command when CI is added.
