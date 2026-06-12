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

    /// Drops known-benign system-level noise lines that Apple CLI tools emit to
    /// stderr on macOS 26 (App Intents/linkd registration chatter, os_log info/debug
    /// records).  Everything else is returned verbatim, in the original order.
    ///
    /// Patterns filtered:
    /// - Any line containing `com.apple.linkd` (covers the
    ///   `Unable to get synchronousRemoteObjectProxy … autoShortcut` multi-word chatter).
    /// - Lines whose first token looks like a timestamp immediately followed by `info` or
    ///   `debug` and a `com.apple.` subsystem
    ///   (format: `YYYY-MM-DDTHH:MM:SS… info com.apple.…`).
    ///
    /// The result is trimmed.
    ///
    /// This is `nonisolated` pure logic — directly testable without any runtime context.
    internal static func filteringSystemNoise(_ input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            // Drop linkd chatter (covers single-line and wrapped variants).
            if line.contains("com.apple.linkd") { return false }

            // Drop timestamped os_log info/debug lines:
            // Pattern: <YYYY-MM-DDTHH:MM:SS…> <space> (info|debug) <space> com.apple.…
            // We do a lightweight prefix scan — no regex — for Swift 6 compatibility.
            // A qualifying line starts with a 4-digit year and a '-'.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 11,
               trimmed[trimmed.startIndex].isNumber,
               trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-" {
                // Find the end of the first whitespace-separated token (the timestamp).
                if let spaceAfterTimestamp = trimmed.firstIndex(of: " ") {
                    let afterTimestamp = trimmed[trimmed.index(after: spaceAfterTimestamp)...]
                    if afterTimestamp.hasPrefix("info com.apple.")
                        || afterTimestamp.hasPrefix("debug com.apple.") {
                        return false
                    }
                }
            }

            return true
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a human-readable failure diagnostic from the raw stdout/stderr of a
    /// failed `container-compose` invocation.
    ///
    /// Strategy (in priority order):
    /// 1. If filtered stderr is non-empty, use it.
    /// 2. If filtered stdout is non-empty, use its **tail** (last 30 lines / ≤2000 chars)
    ///    — compose writes long progress logs to stdout and real errors appear at the end.
    /// 3. If both streams have meaningful content after filtering, include both separated
    ///    by a blank line (stderr first, then the stdout tail).
    /// 4. If both streams are empty after filtering, fall back to
    ///    `"exit code <N> with no output"` so the banner is never blank.
    ///
    /// This is `nonisolated` pure logic — directly testable without any runtime context.
    internal static func failureDiagnostic(stdout: String, stderr: String, exitCode: Int32) -> String {
        let filteredStderr = filteringSystemNoise(strippingANSIEscapes(stderr))
        let filteredStdout = filteringSystemNoise(strippingANSIEscapes(stdout))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Tail of stdout: last 30 lines, capped at 2000 characters.
        let stdoutTail: String = {
            guard !filteredStdout.isEmpty else { return "" }
            let lines = filteredStdout.components(separatedBy: "\n")
            let tail = lines.suffix(30).joined(separator: "\n")
            if tail.count <= 2000 { return tail }
            // Trim from the front to ≤ 2000 chars, preserving line boundaries.
            let truncated = String(tail.suffix(2000))
            // Drop a potentially broken first line.
            if let newline = truncated.firstIndex(of: "\n") {
                return String(truncated[truncated.index(after: newline)...])
            }
            return truncated
        }()

        let hasStderr = !filteredStderr.isEmpty
        let hasStdout = !stdoutTail.isEmpty

        switch (hasStderr, hasStdout) {
        case (true, true):
            return filteredStderr + "\n\n" + stdoutTail
        case (true, false):
            return filteredStderr
        case (false, true):
            return stdoutTail
        case (false, false):
            return "exit code \(exitCode) with no output"
        }
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
        currentDirectoryURL: URL?,
        outputHandler: ProcessOutputHandler? = nil
    ) async throws -> ProcessResult {
        let binaryURL = try await resolvedBinaryURL()
        return try await runner.run(
            executableURL: binaryURL,
            arguments: arguments,
            environment: nil,
            currentDirectoryURL: currentDirectoryURL,
            outputHandler: outputHandler
        )
    }

    /// Runs `container-compose` and maps a non-zero exit to the appropriate
    /// `ContainerRuntimeError`.  Returns trimmed, ANSI-stripped stdout on success.
    @discardableResult
    private func runChecked(
        _ arguments: [String],
        currentDirectoryURL: URL?,
        progress: ComposeProgressHandler? = nil
    ) async throws -> String {
        final class OutputAccumulator: @unchecked Sendable {
            private var output = ""
            private let lock = NSLock()

            func append(_ chunk: String) -> String {
                lock.withLock {
                    output += chunk
                    return output
                }
            }
        }

        let accumulator = OutputAccumulator()
        let result = try await run(
            arguments,
            currentDirectoryURL: currentDirectoryURL
        ) { chunk in
            let output = accumulator.append(chunk)
            progress?(
                String.strippingANSIEscapes(output)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let strippedStdout = String.strippingANSIEscapes(result.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.exitCode != 0 else { return strippedStdout }

        // XPC / apiserver connectivity errors.
        // Check the COMBINED raw streams (unfiltered) — noise cannot false-positive
        // these phrases and we don't want to miss them.
        // Live-verified 2026-06-12: up exits 1, stderr "Error: XPC connection error: Connection invalid"
        let combinedRaw = result.stdout + result.stderr
        if combinedRaw.contains("XPC connection error") || combinedRaw.contains("container system start") {
            throw ContainerRuntimeError.systemNotRunning
        }

        // Build a noise-filtered, human-readable diagnostic.  `failureDiagnostic`
        // strips ANSI and system noise from both streams, prefers stderr, falls back
        // to the stdout tail, and never returns a blank string.
        let diagnostic = String.failureDiagnostic(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode
        )

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
    func up(
        project: ComposeProject,
        services: [String],
        rebuild: Bool,
        noCache: Bool,
        progress: @escaping ComposeProgressHandler
    ) async throws -> String {
        var args = fileArguments(for: project)
        args.append("up")
        args.append("-d")
        if rebuild { args.append("-b") }
        if noCache { args.append("--no-cache") }
        args.append(contentsOf: services)
        return try await runChecked(
            args,
            currentDirectoryURL: projectCWD(for: project),
            progress: progress
        )
    }

    /// `container-compose build [--no-cache] [services…]`
    func build(
        project: ComposeProject,
        services: [String],
        noCache: Bool,
        progress: @escaping ComposeProgressHandler
    ) async throws -> String {
        var args = fileArguments(for: project)
        args.append("build")
        if noCache { args.append("--no-cache") }
        args.append(contentsOf: services)
        return try await runChecked(
            args,
            currentDirectoryURL: projectCWD(for: project),
            progress: progress
        )
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
