import Foundation

// MARK: - ANSI / carriage-return stripping helpers

extension String {
    /// Removes CSI escape sequences (`ESC [ … m` and similar) and collapses
    /// `\r`-rewritten progress lines (keeping only the final state of each segment).
    ///
    /// `container-compose` uses Rainbow for coloured output and overwrites
    /// progress lines in-place using `\r`.  Both artefacts are removed here so
    /// the stored "last output" is readable plain text.
    ///
    /// This is `nonisolated` pure logic — it is directly testable without any
    /// runtime or actor context.
    internal static func strippingANSIEscapes(_ input: String) -> String {
        // Step 1: collapse \r-rewritten lines — keep only the last \r-separated
        // segment on each \n-delimited line.
        let lineCollapsed = input
            .components(separatedBy: "\n")
            .map { line -> String in
                // Split by \r and keep the last non-empty segment, or the last
                // segment if all are empty (preserves blank lines).
                let segments = line.components(separatedBy: "\r")
                return segments.last(where: { !$0.isEmpty }) ?? (segments.last ?? "")
            }
            .joined(separator: "\n")

        // Step 2: strip CSI escape sequences: ESC [ <params> <final-byte>
        // Regex: \u{1B}\[[0-9;]*[A-Za-z]
        // We use a manual scan for Swift 6 compatibility without regex literals.
        var result = ""
        result.reserveCapacity(lineCollapsed.count)
        var idx = lineCollapsed.startIndex

        while idx < lineCollapsed.endIndex {
            let ch = lineCollapsed[idx]
            // Look for ESC (\u{1B})
            if ch == "\u{1B}" {
                let next = lineCollapsed.index(after: idx)
                if next < lineCollapsed.endIndex && lineCollapsed[next] == "[" {
                    // Consume the CSI sequence: skip chars until a letter [A-Za-z]
                    var scanIdx = lineCollapsed.index(after: next)
                    while scanIdx < lineCollapsed.endIndex {
                        let c = lineCollapsed[scanIdx]
                        scanIdx = lineCollapsed.index(after: scanIdx)
                        if c.isLetter {
                            // Final byte consumed — move idx past the sequence.
                            idx = scanIdx
                            break
                        }
                    }
                    // If we never found a final byte (malformed), idx is already
                    // past the '['; the loop will advance to avoid infinite loops.
                    continue
                }
            }
            result.append(ch)
            idx = lineCollapsed.index(after: idx)
        }

        return result
    }
}

// MARK: - ContainerComposeCLIRuntime

/// A `ComposeRuntime` implementation that shells out to the `container-compose`
/// CLI (0.12.0+).  All interaction is non-interactive: `ProcessRunner` sets
/// `/dev/null` as stdin so prompts fail immediately rather than hanging.
///
/// Binary discovery order (first hit wins, result cached per UserDefaults key):
///   1. UserDefaults `containerComposeCLIPath` (trimmed, non-empty, must be executable)
///   2. `executableOverride` supplied at init time
///   3. `/usr/local/bin/container-compose`
///   4. `/opt/homebrew/bin/container-compose`
///   5. `/usr/bin/which container-compose` (trimmed stdout, exit 0 only)
///
/// Failure throws `ContainerRuntimeError.composeCLINotFound`.
///
/// Every compose command sets `currentDirectoryURL` to the compose file's parent
/// folder and passes `-f <filename>` so the project name is always derived from
/// the folder (not the filename).
final class ContainerComposeCLIRuntime: ComposeRuntime {

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

    /// Returns the resolved `container-compose` binary URL, consulting the cache first.
    /// Throws `ContainerRuntimeError.composeCLINotFound` when all candidates fail.
    ///
    /// Discovery order (first hit wins):
    ///   1. UserDefaults `containerComposeCLIPath` (trimmed, non-empty, must be executable)
    ///   2. `executableOverride` supplied at init time
    ///   3. `/usr/local/bin/container-compose`
    ///   4. `/opt/homebrew/bin/container-compose`
    ///   5. `/usr/bin/which container-compose` (trimmed stdout, exit 0 only)
    private func resolvedBinaryURL() async throws -> URL {
        // Read the UserDefaults override on every call (cheap, thread-safe).
        let udRaw = UserDefaults.standard.string(forKey: "containerComposeCLIPath") ?? ""
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
        }

        // 2. Explicit init-time override (trusts the caller; skip existence check).
        if let override = executableOverride {
            await cache.set(override, forKey: udOverride)
            return override
        }

        // 3–4. Well-known installation paths.
        let candidates = [
            URL(fileURLWithPath: "/usr/local/bin/container-compose"),
            URL(fileURLWithPath: "/opt/homebrew/bin/container-compose"),
        ]
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            await cache.set(url, forKey: udOverride)
            return url
        }

        // 5. `which container-compose` — only trust a clean exit-0 with non-empty output.
        let whichURL = URL(fileURLWithPath: "/usr/bin/which")
        let whichResult = try await runner.run(
            executableURL: whichURL,
            arguments: ["container-compose"],
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

        throw ContainerRuntimeError.composeCLINotFound
    }

    // MARK: - Internal helpers

    /// Runs `container-compose` with the given arguments and working directory,
    /// returning the raw result.
    private func run(
        _ arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> ProcessResult {
        let binaryURL = try await resolvedBinaryURL()
        return try await runner.run(
            executableURL: binaryURL,
            arguments: arguments,
            environment: nil,
            currentDirectoryURL: currentDirectoryURL
        )
    }

    /// Runs `container-compose` and maps a non-zero exit to the appropriate
    /// `ContainerRuntimeError`.  Returns trimmed, ANSI-stripped stdout on success.
    @discardableResult
    private func runChecked(
        _ arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> String {
        let result = try await run(arguments, currentDirectoryURL: currentDirectoryURL)
        let strippedStdout = String.strippingANSIEscapes(result.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.exitCode != 0 else { return strippedStdout }

        // Combine stderr and stdout for error mapping (compose writes errors to stderr).
        let combined = result.stderr.isEmpty ? result.stdout : result.stderr
        let strippedCombined = String.strippingANSIEscapes(combined)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Also check stdout for XPC errors (compose sometimes writes to stdout).
        let diagnostic = strippedCombined.isEmpty ? strippedStdout : strippedCombined

        // XPC / apiserver connectivity errors.
        // Live-verified 2026-06-12: up exits 1, stderr "Error: XPC connection error: Connection invalid"
        if diagnostic.contains("XPC connection error") || diagnostic.contains("container system start") {
            throw ContainerRuntimeError.systemNotRunning
        }

        throw ContainerRuntimeError.commandFailed(
            exitCode: result.exitCode,
            stderr: diagnostic
        )
    }

    /// Builds the common argument prefix: `["-f", "<filename>"]`.
    /// The process cwd is always set to the compose file's parent directory so
    /// that the project name is derived from the folder (not the filename).
    private func fileArguments(for project: ComposeProject) -> [String] {
        ["-f", project.fileURL.lastPathComponent]
    }

    private func projectCWD(for project: ComposeProject) -> URL {
        project.fileURL.deletingLastPathComponent()
    }

    // MARK: - ComposeRuntime

    /// `container-compose up -d [-b] [--no-cache] [services…]`
    func up(project: ComposeProject, services: [String], rebuild: Bool, noCache: Bool) async throws -> String {
        var args = fileArguments(for: project)
        args.append("up")
        args.append("-d")
        if rebuild { args.append("-b") }
        if noCache { args.append("--no-cache") }
        args.append(contentsOf: services)
        return try await runChecked(args, currentDirectoryURL: projectCWD(for: project))
    }

    /// `container-compose build [--no-cache] [services…]`
    func build(project: ComposeProject, services: [String], noCache: Bool) async throws -> String {
        var args = fileArguments(for: project)
        args.append("build")
        if noCache { args.append("--no-cache") }
        args.append(contentsOf: services)
        return try await runChecked(args, currentDirectoryURL: projectCWD(for: project))
    }

    /// `container-compose --version` — availability probe.
    ///
    /// Returns trimmed stdout on exit 0, `nil` on any failure (including binary not found).
    /// Never throws.
    func version() async -> String? {
        do {
            let binaryURL = try await resolvedBinaryURL()
            let result = try await runner.run(
                executableURL: binaryURL,
                arguments: ["--version"],
                environment: nil
            )
            guard result.exitCode == 0 else { return nil }
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
