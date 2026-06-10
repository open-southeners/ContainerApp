import Testing
import Foundation
@testable import ContainerBar

// MARK: - TerminalLauncher unit tests
//
// These tests cover only `shellCommand(forContainerID:executablePath:)` — the
// pure, side-effect-free layer — so they never pop a Terminal window or trigger
// the macOS Automation consent prompt.

@Suite("TerminalLauncher.shellCommand")
struct TerminalLauncherTests {

    // MARK: Valid identifiers

    @Test("Valid plain id builds exact expected command")
    func validPlainID() {
        let command = TerminalLauncher.shellCommand(forContainerID: "plan-test")
        #expect(command == "container exec -it plan-test /bin/sh")
    }

    @Test("Valid id with digits and dots")
    func validIDWithDotsAndDigits() {
        let command = TerminalLauncher.shellCommand(forContainerID: "my.container.1")
        #expect(command == "container exec -it my.container.1 /bin/sh")
    }

    @Test("Valid id with underscores and hyphens")
    func validIDWithUnderscoresHyphens() {
        // Underscores are NOT in the allowed set per spec (^[A-Za-z0-9._-]+$),
        // so only letters, digits, period, and hyphen are allowed.
        // Hyphen mid-string is valid.
        let command = TerminalLauncher.shellCommand(forContainerID: "my-container")
        #expect(command == "container exec -it my-container /bin/sh")
    }

    // MARK: Explicit executablePath

    @Test("Explicit executablePath is used instead of default 'container'")
    func explicitExecutablePath() {
        let command = TerminalLauncher.shellCommand(
            forContainerID: "plan-test",
            executablePath: "/usr/local/bin/container"
        )
        #expect(command == "/usr/local/bin/container exec -it plan-test /bin/sh")
    }

    @Test("Explicit executablePath with custom binary name")
    func explicitExecutablePathCustomBinary() {
        let command = TerminalLauncher.shellCommand(
            forContainerID: "myapp",
            executablePath: "/opt/homebrew/bin/container"
        )
        #expect(command == "/opt/homebrew/bin/container exec -it myapp /bin/sh")
    }

    // MARK: Rejected identifiers (nil)

    @Test("Empty string id is rejected")
    func rejectedEmptyString() {
        let command = TerminalLauncher.shellCommand(forContainerID: "")
        #expect(command == nil)
    }

    @Test("Id with space is rejected")
    func rejectedIdWithSpace() {
        let command = TerminalLauncher.shellCommand(forContainerID: "a b")
        #expect(command == nil)
    }

    @Test("Id with double quote is rejected")
    func rejectedIdWithDoubleQuote() {
        let command = TerminalLauncher.shellCommand(forContainerID: "my\"container")
        #expect(command == nil)
    }

    @Test("Id with $( is rejected (command substitution injection)")
    func rejectedIdWithDollarParen() {
        let command = TerminalLauncher.shellCommand(forContainerID: "$(rm -rf ~)")
        #expect(command == nil)
    }

    @Test("Id with semicolon is rejected")
    func rejectedIdWithSemicolon() {
        let command = TerminalLauncher.shellCommand(forContainerID: "a;b")
        #expect(command == nil)
    }

    @Test("Id with backtick is rejected (command substitution injection)")
    func rejectedIdWithBacktick() {
        let command = TerminalLauncher.shellCommand(forContainerID: "`id`")
        #expect(command == nil)
    }

    @Test("Id with leading hyphen is rejected (flag injection)")
    func rejectedLeadingHyphen() {
        let command = TerminalLauncher.shellCommand(forContainerID: "-rm")
        #expect(command == nil)
    }
}
