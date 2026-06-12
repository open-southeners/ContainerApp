import Foundation

// MARK: - ContainerCLIRuntime

/// A `ContainerRuntime` implementation that shells out to the Apple `container`
/// CLI (1.0.0+).  All interaction is non-interactive: `ProcessRunner` sets
/// `/dev/null` as stdin so prompts fail immediately rather than hanging.
///
/// Binary discovery order (first hit wins, result cached per UserDefaults key):
///   1. UserDefaults `containerCLIPath` (trimmed, non-empty, must be executable)
///   2. `executableOverride` supplied at init time
///   3. `/usr/local/bin/container`
///   4. `/opt/homebrew/bin/container`
///   5. `/usr/bin/which container` (trimmed stdout, exit 0 only)
///
/// The cache is keyed by the current UserDefaults override so that editing the
/// Settings pane immediately invalidates the cached path on the next refresh.
/// A UserDefaults path that is missing or not executable falls through silently
/// to the rest of the chain.
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
    ///
    /// Discovery order (first hit wins):
    ///   1. UserDefaults `containerCLIPath` (trimmed, non-empty, must be executable)
    ///   2. `executableOverride` supplied at init time
    ///   3. `/usr/local/bin/container`
    ///   4. `/opt/homebrew/bin/container`
    ///   5. `/usr/bin/which container` (trimmed stdout, exit 0 only)
    ///
    /// The cache is keyed by the current UserDefaults override string so that
    /// editing the setting in the UI immediately invalidates the cached result.
    /// UserDefaults is thread-safe to read from any isolation context.
    private func resolvedBinaryURL() async throws -> URL {
        // Read the UserDefaults override on every call (cheap, thread-safe).
        // Trim whitespace so an accidental trailing newline is ignored.
        let udRaw = UserDefaults.standard.string(forKey: "containerCLIPath") ?? ""
        let udOverride: String? = {
            let trimmed = udRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        // Fast path: cache hit for the current override key.
        if let cached = await cache.get(forKey: udOverride) {
            return cached
        }

        let fm = FileManager.default

        // 1. UserDefaults override — must exist and be executable; otherwise fall through.
        if let udPath = udOverride {
            let udURL = URL(fileURLWithPath: udPath)
            if fm.isExecutableFile(atPath: udURL.path) {
                await cache.set(udURL, forKey: udOverride)
                return udURL
            }
            // Non-executable override: fall through to standard discovery below
            // (cache miss stays; next refresh will retry).
        }

        // 2. Explicit init-time override (trusts the caller; skip existence check).
        if let override = executableOverride {
            await cache.set(override, forKey: udOverride)
            return override
        }

        // 3–4. Well-known installation paths.
        let candidates = [
            URL(fileURLWithPath: "/usr/local/bin/container"),
            URL(fileURLWithPath: "/opt/homebrew/bin/container"),
        ]
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            await cache.set(url, forKey: udOverride)
            return url
        }

        // 5. `which container` — only trust a clean exit-0 with non-empty output.
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
                await cache.set(url, forKey: udOverride)
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

    /// `container start <id>`
    func start(id: String) async throws {
        try await runChecked(["start", id], id: id)
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

    /// `container prune` — removes all stopped containers.
    func pruneContainers() async throws {
        try await runChecked(["prune"])
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
        // Non-interactive stdin causes "failed to read user input".
        // Only these verified phrases indicate the kernel-not-configured scenario;
        // other errors fall through to the generic commandFailed mapping below.
        let lower = trimmed.lowercased()
        if lower.contains("failed to read user input")
            || lower.contains("no default kernel configured")
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

    // MARK: - Image management

    /// `container image list --format json` decoded via `FlexibleContainerDecoder`.
    func listImages() async throws -> [ImageSummary] {
        let result = try await runChecked(["image", "list", "--format", "json"])
        return try FlexibleContainerDecoder.decodeImages(from: result.stdout)
    }

    /// `container image inspect <reference>` — returns the raw stdout string.
    ///
    /// The CLI prints pretty-printed JSON by default; there is no `--format` flag
    /// for this subcommand.  The existing "not found" mapping in `runChecked` gives
    /// `.notFound(id:)` for free when the reference is unknown.
    func inspectImage(reference: String) async throws -> String {
        let result = try await runChecked(["image", "inspect", reference], id: reference)
        return result.stdout
    }

    /// `container image delete <reference>` — removes the image from the local store.
    ///
    /// No `--force` flag is passed: if the CLI refuses (e.g. the image is in use),
    /// the stderr flows through `.commandFailed` into the existing error banner.
    func deleteImage(reference: String) async throws {
        try await runChecked(["image", "delete", reference], id: reference)
    }

    /// `container image prune` — removes dangling images.
    ///
    /// Returns the trimmed stdout summary line from the CLI, e.g.
    /// `"Reclaimed Zero KB in disk space"`.
    func pruneImages() async throws -> String {
        let result = try await runChecked(["image", "prune"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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
