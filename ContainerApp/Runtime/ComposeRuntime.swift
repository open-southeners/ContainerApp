import Foundation

typealias ComposeProgressHandler = @Sendable (String) -> Void

// MARK: - ComposeRuntime

/// Abstraction over the `container-compose` binary.
///
/// Compose is a separate binary with its own lifecycle and binary discovery chain,
/// so it gets its own seam rather than widening `ContainerRuntime`.
///
/// `down` is intentionally absent: `container-compose down` 0.12.0 has an XPC
/// protocol mismatch against container runtime 1.0.0 and does not stop containers
/// reliably.  Stop/teardown is handled in the view model via `ContainerRuntime.stop(id:)`
/// on the matched running containers.  Revisit when the brew formula reaches 1.0.0+.
protocol ComposeRuntime: Sendable {
    /// `container-compose up -d [-b] [--no-cache] [services…]`, cwd = compose folder.
    ///
    /// Passes `-f <filename>` so project-name derivation is always based on the folder
    /// (not the filename), and sets `currentDirectoryURL` to the compose file's parent
    /// directory.  Always runs detached (`-d`) so the call completes after services start.
    ///
    /// - Returns: Trimmed, ANSI-stripped stdout for the per-project "last output" panel.
    func up(
        project: ComposeProject,
        services: [String],
        rebuild: Bool,
        noCache: Bool,
        progress: @escaping ComposeProgressHandler
    ) async throws -> String

    /// `container-compose build [--no-cache] [services…]`
    ///
    /// - Returns: Trimmed, ANSI-stripped stdout for the per-project "last output" panel.
    func build(
        project: ComposeProject,
        services: [String],
        noCache: Bool,
        progress: @escaping ComposeProgressHandler
    ) async throws -> String

    /// `container-compose --version` — availability probe.
    ///
    /// - Returns: The version string (e.g. `"container-compose version 0.12.0"`) on success,
    ///   or `nil` when the binary is missing or the command fails for any reason.
    ///   **Never throws** — callers use the return value to drive install prompts.
    func version() async -> String?
}
