import Testing
import Foundation
@testable import ContainerApp

// MARK: - Availability gate helper (compose binary)

/// Returns `true` when a `container-compose` binary is discoverable on this machine.
/// Checks the same well-known paths as `ContainerComposeCLIRuntime` plus `which`.
private func composeIsAvailable() -> Bool {
    let wellKnown = [
        "/usr/local/bin/container-compose",
        "/opt/homebrew/bin/container-compose",
    ]
    for path in wellKnown where FileManager.default.isExecutableFile(atPath: path) {
        return true
    }

    // Fall back to `which container-compose`.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["container-compose"]
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

// MARK: - ANSI / carriage-return stripping unit tests

@Suite("ContainerComposeCLIRuntime.strippingANSIEscapes")
struct ANSIStrippingTests {

    @Test("Plain text is returned unchanged")
    func plainTextUnchanged() {
        let input = "web: started\ndb: started"
        #expect(String.strippingANSIEscapes(input) == input)
    }

    @Test("Empty string is returned unchanged")
    func emptyStringUnchanged() {
        #expect(String.strippingANSIEscapes("") == "")
    }

    @Test("CSI colour escape codes are removed")
    func ansiColorCodesRemoved() {
        // ESC[32m = green, ESC[0m = reset
        let input = "\u{1B}[32mSuccess\u{1B}[0m"
        #expect(String.strippingANSIEscapes(input) == "Success")
    }

    @Test("Multiple CSI sequences in one line are all removed")
    func multipleEscapesInOneLine() {
        let input = "\u{1B}[1m\u{1B}[32mBold green\u{1B}[0m normal"
        #expect(String.strippingANSIEscapes(input) == "Bold green normal")
    }

    @Test("CSI sequence with multiple params (e.g. 38;5;196) is removed")
    func multiParamEscapeRemoved() {
        let input = "\u{1B}[38;5;196mRed256\u{1B}[0m"
        #expect(String.strippingANSIEscapes(input) == "Red256")
    }

    @Test("Carriage-return progress lines are collapsed to last segment")
    func carriageReturnCollapsed() {
        // Simulates: progress output overwritten via \r
        let input = "Pulling...\rPulling...done"
        #expect(String.strippingANSIEscapes(input) == "Pulling...done")
    }

    @Test("Multiple carriage-return overwrites keep final state")
    func multipleCarriageReturnsKeepLast() {
        let input = "10%\r50%\r100%"
        #expect(String.strippingANSIEscapes(input) == "100%")
    }

    @Test("Multiline output with per-line CR collapse works correctly")
    func multilineCarriageReturnCollapse() {
        let input = "line1\rline1-done\nline2\rline2-done"
        #expect(String.strippingANSIEscapes(input) == "line1-done\nline2-done")
    }

    @Test("Combined ANSI codes and carriage-return are both stripped")
    func combinedANSIAndCarriageReturn() {
        let input = "\u{1B}[32m10%\u{1B}[0m\r\u{1B}[32m100%\u{1B}[0m"
        #expect(String.strippingANSIEscapes(input) == "100%")
    }

    @Test("Newline without CR is preserved verbatim")
    func newlinePreserved() {
        let input = "web: started\ndb: started\n"
        #expect(String.strippingANSIEscapes(input) == "web: started\ndb: started\n")
    }

    @Test("ESC not followed by [ is passed through")
    func escNotFollowedByBracketPassThrough() {
        // ESC followed by a non-[ character should not eat any surrounding text.
        let input = "before\u{1B}Xafter"
        #expect(String.strippingANSIEscapes(input) == "before\u{1B}Xafter")
    }
}

// MARK: - Compose CLI integration test

/// Integration tests for `ContainerComposeCLIRuntime` gated on the compose binary
/// being discoverable.  Only `version()` is exercised — `up` and `build` are
/// intentionally not called to avoid pulling images or creating containers on the
/// developer's machine.
@Suite(
    "ContainerComposeCLIRuntime integration",
    .enabled(if: composeIsAvailable(), "container-compose binary is not available")
)
struct ComposeRuntimeIntegrationTests {

    private let runtime = ContainerComposeCLIRuntime()

    @Test("version() returns non-nil string containing 'container-compose version'")
    func versionReturnsVersionString() async {
        let v = await runtime.version()
        #expect(v != nil, "version() should return a non-nil string when the binary is present")
        if let v {
            #expect(v.contains("container-compose version"),
                    "version string '\(v)' should contain 'container-compose version'")
        }
    }
}
