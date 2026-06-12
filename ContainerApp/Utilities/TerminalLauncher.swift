import Foundation
import os

// MARK: - TerminalLauncher

/// Namespace for opening a shell inside a running container in Terminal.app.
///
/// Implemented as a caseless enum (no instances) so that the two layers are
/// clearly separated: `shellCommand(forContainerID:executablePath:)` is pure and
/// unit-testable without side effects; `open(command:)` owns the AppleScript
/// side effect.
///
/// - Note: The first call to `open(command:)` triggers the macOS Automation
///   consent prompt for Terminal.app.  `NSAppleEventsUsageDescription` is
///   already declared in `Info.plist` (added in Phase 0).  Denial of the prompt
///   has no programmatic recovery; failures are logged and swallowed.
enum TerminalLauncher {

    // MARK: Private

    private static let logger = Logger(
        subsystem: "com.opensoutheners.ContainerApp",
        category: "TerminalLauncher"
    )

    // MARK: - Command construction

    /// Builds the shell command used to exec into a container.
    ///
    /// Returns `nil` when `id` fails validation so that the caller can surface a
    /// meaningful error without ever interpolating an untrusted string into a
    /// shell line.  Validation rules (injection defence — ids are not quoted,
    /// they are embedded verbatim):
    ///
    /// - Must match `^[A-Za-z0-9._-]+$`  (no shell metacharacters)
    /// - Must **not** start with `-`  (would be parsed as a flag by the CLI)
    ///
    /// - Parameters:
    ///   - id: The container identifier returned by the runtime.
    ///   - executablePath: An explicit path to the `container` binary.  When
    ///     `nil` the plain name `container` is used — Terminal login shells
    ///     receive `/usr/local/bin` via `/etc/paths`, so the binary resolves
    ///     without an absolute path.  A custom path here enables the Phase 4
    ///     Settings override.
    /// - Returns: A shell command string, or `nil` if `id` is invalid.
    static func shellCommand(
        forContainerID id: String,
        executablePath: String? = nil
    ) -> String? {
        // Reject empty ids early (the regex below would also reject them, but
        // an explicit guard makes the intent unmistakable).
        guard !id.isEmpty else { return nil }

        // Reject ids that begin with `-` to prevent flag injection even when the
        // character set check would otherwise pass (e.g. "-mycontainer").
        guard !id.hasPrefix("-") else { return nil }

        // Allow only the characters that appear in valid container identifiers.
        // Any shell metacharacter (space, $, (, ), >, |, ;, \, ", ', `, & …)
        // causes an early nil return here.
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard id.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }

        let binary = executablePath ?? "container"
        return "\(binary) exec -it \(id) /bin/sh"
    }

    // MARK: - AppleScript launcher

    /// Opens Terminal.app and runs `command` in a new window.
    ///
    /// The command is embedded inside an AppleScript string literal.  To
    /// prevent the AppleScript interpreter from misreading the string, two
    /// characters are escaped *in order*:
    ///
    /// 1. Backslashes (`\` → `\\`) — escape the escape character first so that
    ///    a later replacement cannot accidentally double-escape a quote.
    /// 2. Double quotes (`"` → `\"`) — AppleScript string delimiter.
    ///
    /// The resulting script is passed to `/usr/bin/osascript -e` via
    /// `Foundation.Process`.  The call is fire-and-forget (`try? process.run()`);
    /// any launch failure is logged at fault level rather than thrown because
    /// the Automation consent-denial path offers no useful programmatic recovery.
    ///
    /// `MainActor` isolation is **not** required: this method touches no AppKit
    /// or SwiftUI state.  `TerminalLauncher` itself has no mutable state, so it
    /// satisfies Swift 6 `Sendable` constraints naturally.
    ///
    /// - Parameter command: The shell command to execute in the new Terminal tab.
    static func open(command: String) {
        // Escape for embedding inside an AppleScript double-quoted string.
        // Order matters: backslashes must be doubled before quotes are escaped.
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
        } catch {
            logger.fault("TerminalLauncher: osascript launch failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}
