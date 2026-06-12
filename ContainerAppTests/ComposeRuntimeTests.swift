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

// MARK: - System-noise filter unit tests

@Suite("ContainerComposeCLIRuntime.filteringSystemNoise")
struct SystemNoiseFilterTests {

    @Test("Plain text with no noise is returned unchanged")
    func plainTextUnchanged() {
        let input = "Error: volume 'mydata' already exists\nService 'web' failed to start"
        #expect(String.filteringSystemNoise(input) == input)
    }

    @Test("Empty string is returned unchanged")
    func emptyStringUnchanged() {
        #expect(String.filteringSystemNoise("") == "")
    }

    @Test("linkd chatter line is dropped")
    func linkdLineDropped() {
        let input = "Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 \"connection to service named com.apple.linkd.autoShortcut\""
        #expect(String.filteringSystemNoise(input) == "")
    }

    @Test("os_log info line for com.apple subsystem is dropped")
    func osLogInfoLineDropped() {
        let input = "2026-06-12T10:30:00.123+0000 info com.apple.container.apiserver: Starting up"
        #expect(String.filteringSystemNoise(input) == "")
    }

    @Test("os_log debug line for com.apple subsystem is dropped")
    func osLogDebugLineDropped() {
        let input = "2026-06-12T10:30:00.456+0000 debug com.apple.container.runtime: Checkpoint reached"
        #expect(String.filteringSystemNoise(input) == "")
    }

    @Test("os_log warning line is kept (not in filtered set)")
    func osLogWarningLineKept() {
        let input = "2026-06-12T10:30:00.789+0000 warning com.apple.container.apiserver: Out of memory"
        #expect(String.filteringSystemNoise(input) == input)
    }

    @Test("Real error line is kept when mixed with noise lines")
    func realErrorLineKeptAmidNoise() {
        let linkdNoise = "Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 \"connection to service named com.apple.linkd.autoShortcut\""
        let osLogNoise = "2026-06-12T10:30:00.123+0000 info com.apple.container: doing stuff"
        let realError = "Error: failed to create volume 'mydata': volume already exists"
        let input = [linkdNoise, osLogNoise, realError].joined(separator: "\n")
        #expect(String.filteringSystemNoise(input) == realError)
    }

    @Test("Multiple real error lines are kept in original order")
    func multipleRealErrorLinesPreserved() {
        let noise = "2026-06-12T08:00:00.000+0000 debug com.apple.container.runtime: init"
        let err1 = "Error processing service 'db'"
        let err2 = "volume 'pgdata' not found"
        let input = [noise, err1, err2].joined(separator: "\n")
        #expect(String.filteringSystemNoise(input) == [err1, err2].joined(separator: "\n"))
    }

    @Test("Line with timestamp but non-apple subsystem is kept")
    func timestampedNonAppleLineKept() {
        let input = "2026-06-12T10:30:00.000+0000 info myapp.custom: initialized"
        #expect(String.filteringSystemNoise(input) == input)
    }

    @Test("Result is trimmed of leading and trailing whitespace")
    func resultIsTrimmed() {
        let noise1 = "2026-06-12T10:00:00.000+0000 info com.apple.container: startup"
        let noise2 = "2026-06-12T10:00:01.000+0000 debug com.apple.container: tick"
        let input = noise1 + "\n" + noise2
        #expect(String.filteringSystemNoise(input) == "")
    }
}

// MARK: - failureDiagnostic unit tests

@Suite("ContainerComposeCLIRuntime.failureDiagnostic")
struct FailureDiagnosticTests {

    // Convenience alias for readability.
    private func diagnostic(stdout: String = "", stderr: String = "", exitCode: Int32 = 1) -> String {
        String.failureDiagnostic(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }

    @Test("Clean stderr is returned as-is")
    func cleanStderrReturned() {
        let result = diagnostic(stdout: "", stderr: "Error: volume creation failed")
        #expect(result == "Error: volume creation failed")
    }

    @Test("Noisy stderr with real stdout error falls back to stdout tail")
    func noisyStderrFallsBackToStdout() {
        let linkdNoise = "Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 \"connection to service named com.apple.linkd.autoShortcut\""
        let realError = "Error: failed to process service 'web': image not found"
        let result = diagnostic(stdout: realError, stderr: linkdNoise)
        #expect(result == realError)
    }

    @Test("Real stderr takes priority over stdout content")
    func realStderrPrioritisedOverStdout() {
        let stderrErr = "Error: XPC connection failed"
        let stdoutContent = "Pulling image...\nPull complete"
        // Note: XPC phrase triggers systemNotRunning before failureDiagnostic in runChecked,
        // but the helper itself should still surface stderr when present.
        let result = diagnostic(stdout: stdoutContent, stderr: stderrErr)
        #expect(result.contains(stderrErr))
    }

    @Test("Both non-empty streams are combined with separator")
    func bothStreamsCombined() {
        let stderrContent = "Warning: deprecated config option"
        let stdoutContent = "Error: failed to start service"
        let result = diagnostic(stdout: stdoutContent, stderr: stderrContent)
        #expect(result.contains(stderrContent))
        #expect(result.contains(stdoutContent))
        // They should be separated by a blank line.
        #expect(result.contains("\n\n"))
    }

    @Test("All-noise streams produce exit-code fallback")
    func allNoiseProducesExitCodeFallback() {
        let linkdNoise = "connection to service named com.apple.linkd.autoShortcut"
        let osLogNoise = "2026-06-12T10:00:00.000+0000 info com.apple.container: tick"
        let result = diagnostic(stdout: osLogNoise, stderr: linkdNoise, exitCode: 1)
        #expect(result == "exit code 1 with no output")
    }

    @Test("All-noise streams use the correct exit code in fallback")
    func exitCodeUsedInFallback() {
        let noise = "connection to service named com.apple.linkd.autoShortcut"
        let result = diagnostic(stdout: "", stderr: noise, exitCode: 137)
        #expect(result == "exit code 137 with no output")
    }

    @Test("Empty stdout and empty stderr produce exit-code fallback")
    func emptyStreamsProduceExitCodeFallback() {
        let result = diagnostic(stdout: "", stderr: "", exitCode: 2)
        #expect(result == "exit code 2 with no output")
    }

    @Test("Stdout tail is bounded to last 30 lines")
    func stdoutTailBoundedTo30Lines() {
        let lines = (1...50).map { "Line \($0)" }
        let stdout = lines.joined(separator: "\n")
        let result = diagnostic(stdout: stdout, stderr: "", exitCode: 1)
        // The result should contain the last line but not the first.
        #expect(result.contains("Line 50"))
        #expect(!result.contains("Line 1\n"))
    }

    @Test("ANSI codes in streams are stripped before output")
    func ansiCodesStrippedInDiagnostic() {
        let stderr = "\u{1B}[31mError: volume not found\u{1B}[0m"
        let result = diagnostic(stdout: "", stderr: stderr)
        #expect(result == "Error: volume not found")
    }

    @Test("os_log noise in stderr is filtered when stdout has real error")
    func osLogNoiseInStderrFilteredWithStdoutFallback() {
        let osLogNoise = "2026-06-12T09:00:00.000+0000 debug com.apple.container.runtime: polling"
        let realStdout = "Error: service 'db' failed: port 5432 already in use"
        let result = diagnostic(stdout: realStdout, stderr: osLogNoise)
        #expect(result == realStdout)
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
