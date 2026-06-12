import Foundation

// MARK: - CLI binary discovery helpers
//
// Shared synchronous helpers used by integration-test availability gates.
// `ConditionTrait.enabled(if:)` requires a synchronous predicate, so these
// helpers use a blocking `Process` call for the `which` fallback.

/// Returns the first discoverable path for the `container` binary, or `nil`.
///
/// Discovery order mirrors `ContainerCLIRuntime.resolvedBinaryURL()` — minus the
/// UserDefaults override which is not meaningful in a test context:
///   1. `/usr/local/bin/container`
///   2. `/opt/homebrew/bin/container`
///   3. `which container` (fallback)
func discoverContainerBinaryPath() -> String? {
    let wellKnown = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
    ]
    for path in wellKnown where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }

    // Fall back to `which container`.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["container"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError  = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
}

/// Returns `true` when the `container` binary is discoverable **and**
/// `container system status` exits 0 (system is up).
///
/// Used as a synchronous gate for `ContainerCLIRuntimeIntegrationTests`.
func containerSystemIsAvailable() -> Bool {
    guard let binaryPath = discoverContainerBinaryPath() else { return false }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["system", "status"]
    // Silence output — we only care about the exit code.
    process.standardOutput = FileHandle.nullDevice
    process.standardError  = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    return process.terminationStatus == 0
}
