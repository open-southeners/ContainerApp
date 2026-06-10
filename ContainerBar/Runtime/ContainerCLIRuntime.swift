import Foundation

// MARK: - Binary URL cache (actor for Swift 6 Sendable correctness)

/// Isolated store for the lazily-discovered `container` binary URL.
/// Using an actor avoids `@unchecked Sendable` while keeping the cache
/// mutation safely serialised across concurrent callers.
private actor BinaryCache {
    private var resolvedURL: URL?

    func get() -> URL? { resolvedURL }
    func set(_ url: URL) { resolvedURL = url }
}

// MARK: - ContainerCLIRuntime

/// A `ContainerRuntime` implementation that shells out to the Apple `container`
/// CLI (1.0.0+).  All interaction is non-interactive: `ProcessRunner` sets
/// `/dev/null` as stdin so prompts fail immediately rather than hanging.
///
/// Binary discovery order (first hit wins, result cached):
///   1. `executableOverride` supplied at init time
///   2. `/usr/local/bin/container`
///   3. `/opt/homebrew/bin/container`
///   4. `/usr/bin/which container` (trimmed stdout, exit 0 only)
///
/// If none of the above resolves, every method that needs the binary will
/// throw `ContainerRuntimeError.cliNotFound`.
final class ContainerCLIRuntime: ContainerRuntime {

    // MARK: Stored properties

    private let runner: any ProcessRunning
    private let executableOverride: URL?
    private let cache = BinaryCache()

    // MARK: Init

    init(
        runner: any ProcessRunning = ProcessRunner(),
        executableOverride: URL? = nil
    ) {
        self.runner = runner
        self.executableOverride = executableOverride
    }

    // MARK: - Binary discovery

    /// Returns the resolved binary URL, consulting the cache first.
    /// Throws `ContainerRuntimeError.cliNotFound` when all candidates fail.
    private func resolvedBinaryURL() async throws -> URL {
        // Fast path: already discovered on a previous call.
        if let cached = await cache.get() {
            return cached
        }

        let fm = FileManager.default

        // 1. Explicit override (trusts the caller; skip existence check).
        if let override = executableOverride {
            await cache.set(override)
            return override
        }

        // 2–3. Well-known installation paths.
        let candidates = [
            URL(fileURLWithPath: "/usr/local/bin/container"),
            URL(fileURLWithPath: "/opt/homebrew/bin/container"),
        ]
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            await cache.set(url)
            return url
        }

        // 4. `which container` — only trust a clean exit-0 with non-empty output.
        let whichURL = URL(fileURLWithPath: "/usr/bin/which")
        let whichResult = try await runner.run(
            executableURL: whichURL,
            arguments: ["container"],
            environment: nil
        )
        if whichResult.exitCode == 0 {
            let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                await cache.set(url)
                return url
            }
        }

        throw ContainerRuntimeError.cliNotFound
    }

    // MARK: - Internal helpers

    /// Runs the `container` binary with the given arguments and returns the raw result.
    private func run(_ arguments: [String]) async throws -> ProcessResult {
        let binaryURL = try await resolvedBinaryURL()
        return try await runner.run(
            executableURL: binaryURL,
            arguments: arguments,
            environment: nil
        )
    }

    /// Calls `run(_:)` and maps a non-zero exit code to the appropriate
    /// `ContainerRuntimeError`.  Pass the `id` when the command targets a
    /// specific container so "not found" can be mapped to `.notFound(id:)`.
    @discardableResult
    private func runChecked(_ arguments: [String], id: String? = nil) async throws -> ProcessResult {
        let result = try await run(arguments)
        guard result.exitCode != 0 else { return result }

        // Use stderr as the primary diagnostic; fall back to stdout.
        let combined = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed  = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        // XPC / apiserver connectivity errors.
        if trimmed.contains("XPC connection error") || trimmed.contains("container system start") {
            throw ContainerRuntimeError.systemNotRunning
        }

        // "not found" — only map to .notFound when we have an id to report.
        if let id, trimmed.lowercased().contains("not found") {
            throw ContainerRuntimeError.notFound(id: id)
        }

        // Generic failure: prefer stderr, fall back to stdout.
        throw ContainerRuntimeError.commandFailed(
            exitCode: result.exitCode,
            stderr: trimmed
        )
    }

    // MARK: - ContainerRuntime

    /// `container list --all --format json` decoded via `FlexibleContainerDecoder`.
    func listContainers() async throws -> [ContainerSummary] {
        let result = try await runChecked(["list", "--all", "--format", "json"])
        return try FlexibleContainerDecoder.decodeList(from: result.stdout)
    }

    /// `container inspect <id>` — returns the raw stdout string.
    func inspect(id: String) async throws -> String {
        let result = try await runChecked(["inspect", id], id: id)
        return result.stdout
    }

    /// `container logs -n <lines> <id>` — returns the raw stdout string.
    func logs(id: String, lines: Int) async throws -> String {
        let result = try await runChecked(["logs", "-n", "\(lines)", id], id: id)
        return result.stdout
    }

    /// `container stats --format json --no-stream [<id>]` decoded via `FlexibleContainerDecoder`.
    /// Stats failures are independent — the caller is responsible for deciding
    /// whether to propagate or swallow the error without affecting the container list.
    func stats(id: String?) async throws -> [ContainerStats] {
        var arguments = ["stats", "--format", "json", "--no-stream"]
        if let id { arguments.append(id) }
        let result = try await runChecked(arguments, id: id)
        return try FlexibleContainerDecoder.decodeStats(from: result.stdout)
    }

    /// `container stop <id>`
    func stop(id: String) async throws {
        try await runChecked(["stop", id], id: id)
    }

    /// `container kill <id>`
    func kill(id: String) async throws {
        try await runChecked(["kill", id], id: id)
    }

    /// `container delete <id>`
    func delete(id: String) async throws {
        try await runChecked(["delete", id], id: id)
    }

    /// `container system start`
    ///
    /// The CLI prompts interactively when no kernel is installed.  Because our
    /// stdin is always `/dev/null` the prompt fails with "failed to read user
    /// input".  We catch that and surface a clear message directing the user to
    /// run `container system kernel set --recommended` once to install a kernel.
    /// (A Settings affordance is deferred to Phase 4.)
    func startSystem() async throws {
        let result = try await run(["system", "start"])
        guard result.exitCode != 0 else { return }

        let combined = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed  = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        // Known limitation: first-ever start requires an interactive kernel prompt.
        // Non-interactive stdin causes immediate failure.
        if trimmed.lowercased().contains("failed to read user input")
            || trimmed.lowercased().contains("kernel")
        {
            throw ContainerRuntimeError.commandFailed(
                exitCode: result.exitCode,
                stderr: "A kernel is required before starting the system. "
                    + "Run: container system kernel set --recommended"
            )
        }

        // XPC / apiserver connectivity errors.
        if trimmed.contains("XPC connection error") || trimmed.contains("container system start") {
            throw ContainerRuntimeError.systemNotRunning
        }

        throw ContainerRuntimeError.commandFailed(
            exitCode: result.exitCode,
            stderr: trimmed
        )
    }

    /// `container system stop`
    func stopSystem() async throws {
        try await runChecked(["system", "stop"])
    }

    /// `container system status`
    ///
    /// This method does NOT use `runChecked` so that a non-running system is
    /// reported as `.stopped` rather than thrown as an error.
    ///
    /// - Returns:
    ///   - `.running`  — exit 0
    ///   - `.stopped`  — non-zero exit with output containing "not running"
    ///   - `.unknown`  — any other non-zero exit (first line of output)
    /// - Throws: `ContainerRuntimeError.cliNotFound` when binary discovery fails.
    func systemStatus() async throws -> ContainerSystemStatus {
        // Binary discovery is still allowed to throw (CLI absent is a hard error).
        let result = try await run(["system", "status"])

        if result.exitCode == 0 {
            return .running
        }

        let combined = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed  = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().contains("not running") {
            return .stopped
        }

        // Preserve the first line of output as a hint for the UI.
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? trimmed
        return .unknown(firstLine)
    }
}
