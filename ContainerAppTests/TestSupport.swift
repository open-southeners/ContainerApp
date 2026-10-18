import Foundation

// MARK: - CLI binary discovery helpers
//
// Shared synchronous helpers used by integration-test availability gates.
// `ConditionTrait.enabled(if:)` requires a synchronous predicate, so these
// helpers use a blocking `Process` call for the `which` fallback.

/// Returns the first discoverable path for the `container` binary, or `nil`.
///
/// Discovery order mirrors `ContainerSystemCLI.resolvedBinaryURL()` — minus the
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
/// Used as a synchronous gate for `ContainerAPIRuntimeIntegrationTests`.
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

// MARK: - Fixture loading

/// A concrete class whose bundle contains the Fixtures resources.
private final class FixtureBundleLocator {}

enum FixtureError: Error {
    case notFound(name: String)
}

/// Decodes `Fixtures/<name>.json` — captured `container` CLI output — into `type`.
/// The CLI renders the library's own Codable types with ISO 8601 dates, so the
/// fixtures decode straight into `ManagedContainer`, `ContainerStats` and `ImageResource`.
func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
    let bundle = Bundle(for: FixtureBundleLocator.self)
    // Fixtures are copied as a folder reference, so they live in a "Fixtures" subdirectory
    // inside the test bundle's Resources directory; fall back to a flat lookup.
    guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: "json")
    else {
        throw FixtureError.notFound(name: "\(name).json")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(contentsOf: url))
}
