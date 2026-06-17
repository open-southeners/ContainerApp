import Foundation
import os

// MARK: - DockerCompatInstaller

/// Installs/removes shell `docker` + `docker-compose` shims that translate
/// Docker commands into Apple's `container` / `container-compose` CLIs.
///
/// Implemented as a caseless enum (no instances) with the same two-layer split
/// as `TerminalLauncher`:
///
/// - **Pure layer** — `isInstalled(in:)`, `inserting(into:)`, `removing(from:)`
///   operate on a file's *contents* (a `String`) and are fully unit-testable
///   without touching the filesystem.
/// - **Side-effecting layer** — `status(at:)`, `install(at:)`, `uninstall(at:)`
///   read/write a shell rc file. They take an explicit `URL` (defaulting to the
///   login shell's rc) so tests can target a temp file.
///
/// The shim is written as a reversible, marker-delimited block (conda/nvm
/// style) so installing is idempotent and removing leaves the rest of the rc
/// file untouched.
enum DockerCompatInstaller {

    private static let logger = Logger(
        subsystem: "com.opensoutheners.ContainerApp",
        category: "DockerCompatInstaller"
    )

    // MARK: Markers

    static let beginMarker = "# >>> ContainerApp docker-compat >>>"
    static let endMarker = "# <<< ContainerApp docker-compat <<<"

    // MARK: Shim content

    /// The shell function definitions, without the surrounding markers.
    ///
    /// A plain `alias docker=container` cannot work: Docker keeps `ps`, `images`,
    /// `pull`, `rmi`, `login`, … at the top level while `container` nests/renames
    /// them, so the first argument has to be rewritten. Functions are the only
    /// mechanism that can. Kept in sync with `scripts/docker-compat.sh`.
    static let snippet = """
    # Run `docker` / `docker compose` against Apple's `container` CLIs.
    # Installed by ContainerApp — remove via Settings or delete this block.
    docker() {
      case "$1" in
        images)        shift; command container image list "$@" ;;
        rmi)           shift; command container image delete "$@" ;;
        pull)          shift; command container image pull "$@" ;;
        push)          shift; command container image push "$@" ;;
        tag)           shift; command container image tag "$@" ;;
        load)          shift; command container image load "$@" ;;
        save)          shift; command container image save "$@" ;;
        ps)            shift; command container list "$@" ;;
        container)     shift; docker "$@" ;;
        login)         shift; command container registry login "$@" ;;
        logout)        shift; command container registry logout "$@" ;;
        info)          shift; command container system status "$@" ;;
        version|-v|--version) command container --version ;;
        compose)       shift; command container-compose "$@" ;;
        *)             command container "$@" ;;
      esac
    }
    docker-compose() { command container-compose "$@"; }
    """

    /// The full block written to the rc file, markers included, newline-framed.
    static var block: String {
        "\(beginMarker)\n\(snippet)\n\(endMarker)\n"
    }

    // MARK: Pure layer

    /// Whether the managed block is present in the given file contents.
    static func isInstalled(in contents: String) -> Bool {
        contents.contains(beginMarker)
    }

    /// Returns `contents` with the managed block removed (no-op if absent).
    ///
    /// Also consumes the single newline preceding `beginMarker` and the one
    /// following `endMarker`, so repeated install/uninstall cycles never
    /// accumulate blank lines.
    static func removing(from contents: String) -> String {
        guard let begin = contents.range(of: beginMarker),
              let end = contents.range(of: endMarker),
              begin.lowerBound < end.upperBound
        else { return contents }

        var lo = begin.lowerBound
        var hi = end.upperBound
        // Drop a trailing newline after the end marker.
        if hi < contents.endIndex, contents[hi] == "\n" {
            hi = contents.index(after: hi)
        }
        // Drop a single separating newline before the begin marker.
        if lo > contents.startIndex {
            let prev = contents.index(before: lo)
            if contents[prev] == "\n" { lo = prev }
        }

        var result = contents
        result.removeSubrange(lo..<hi)
        return result
    }

    /// Returns `contents` with the managed block present exactly once, appended
    /// at the end. Idempotent: any existing copy is stripped first so updating
    /// the snippet content replaces the old block rather than duplicating it.
    static func inserting(into contents: String) -> String {
        let stripped = removing(from: contents)
        guard !stripped.isEmpty else { return block }
        let separator = stripped.hasSuffix("\n") ? "\n" : "\n\n"
        return stripped + separator + block
    }

    // MARK: Shell / rc resolution

    enum Shell {
        case zsh
        case bash

        /// The rc file Terminal.app reads for this shell on macOS. zsh reads
        /// `.zshrc` for interactive shells; bash login shells read `.bash_profile`.
        var rcFileName: String {
            switch self {
            case .zsh: ".zshrc"
            case .bash: ".bash_profile"
            }
        }
    }

    /// The user's login shell, derived from `$SHELL` (set even for apps launched
    /// from Finder). Defaults to zsh, the macOS default.
    static func loginShell(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Shell {
        (environment["SHELL"] ?? "").contains("bash") ? .bash : .zsh
    }

    /// The rc file that `install`/`uninstall` target by default.
    static func defaultRCURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: Shell = DockerCompatInstaller.loginShell()
    ) -> URL {
        home.appendingPathComponent(shell.rcFileName)
    }

    // MARK: Side-effecting layer

    /// Reads `url` and reports whether the managed block is installed.
    /// A missing file reads as "not installed".
    static func status(at url: URL = DockerCompatInstaller.defaultRCURL()) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return isInstalled(in: contents)
    }

    /// Installs (or refreshes) the managed block in `url`, creating the file if
    /// it does not exist.
    static func install(at url: URL = DockerCompatInstaller.defaultRCURL()) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = inserting(into: existing)
        try write(updated, to: url)
        logger.info("Installed docker-compat block into \(url.path, privacy: .public)")
    }

    /// Removes the managed block from `url`. No-op if the file or block is absent.
    static func uninstall(at url: URL = DockerCompatInstaller.defaultRCURL()) throws {
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return }
        let updated = removing(from: existing)
        guard updated != existing else { return }
        try write(updated, to: url)
        logger.info("Removed docker-compat block from \(url.path, privacy: .public)")
    }

    private static func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
