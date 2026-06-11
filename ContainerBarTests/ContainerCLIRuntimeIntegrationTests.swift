import Testing
import Foundation
@testable import ContainerBar

// MARK: - Availability gate helpers
//
// The whole suite is gated behind a synchronous check so it skips cleanly on
// machines that don't have the `container` CLI installed or where the container
// system service is not running.  Using a synchronous `Process` call here is
// intentional — `ConditionTrait.enabled(if:)` requires a synchronous predicate.

/// Returns `true` when:
///   1. `/usr/local/bin/container` is executable, AND
///   2. `container system status` exits 0 (system is up).
private func containerSystemIsAvailable() -> Bool {
    let binaryPath = "/usr/local/bin/container"
    guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
        return false
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["system", "status"]
    // Silence output — we only care about the exit code.
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

// MARK: - Unique container name helper

/// Creates a container name that is unique enough for the test run.
/// Format: phase3-it-<suffix>  (matches the plan spec and passes id validation).
private func uniqueContainerName(suffix: String) -> String {
    "phase3-it-\(suffix)"
}

// MARK: - Direct CLI helper (used to create/destroy scratch containers)

/// Runs `container <arguments>` synchronously and returns the exit code.
/// Used for setup/teardown where async concurrency is not needed.
@discardableResult
private func runCLI(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError  = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

// MARK: - Integration suite

/// Integration tests that exercise `ContainerCLIRuntime` against the real
/// Apple `container` system service.
///
/// The entire suite is gated with `.enabled(if:)` so it skips cleanly on
/// machines where the service is not available (e.g. CI environments).
///
/// The suite is `.serialized` because it shares scratch containers — CLI
/// operations against the same service are not snapshot-isolated.
@Suite(
    "ContainerCLIRuntime integration",
    .enabled(if: containerSystemIsAvailable(), "container system is not available"),
    .serialized
)
struct ContainerCLIRuntimeIntegrationTests {

    // MARK: Shared runtime

    /// A fresh `ContainerCLIRuntime` pointing at the default binary path.
    private let runtime = ContainerCLIRuntime()

    // MARK: - Test 1: Full lifecycle

    /// Creates a scratch container, exercises every major runtime method against
    /// it, then prunes it away.
    ///
    /// Lifecycle: run → list (running) → logs → inspect → stop → list (stopped) → prune → gone.
    @Test("Lifecycle: run → list → logs → inspect → stop → prune", .timeLimit(.minutes(2)))
    func lifecycle() async throws {
        let name = uniqueContainerName(suffix: "1")

        // Teardown: forcibly delete the container even if the test fails.
        defer { runCLI(["delete", "--force", name]) }

        // --- Setup: create the container via the CLI directly ---
        let runCode = runCLI([
            "run", "-d", "--name", name,
            "alpine:latest", "sleep", "120",
        ])
        #expect(runCode == 0, "container run should succeed (exit 0), got \(runCode)")

        // Give the daemon a moment to register the container.
        try await Task.sleep(for: .seconds(2))

        // --- 1. listContainers() contains it with state .running ---
        let containersAfterRun = try await runtime.listContainers()
        let found = containersAfterRun.first(where: { $0.id == name })
        let container = try #require(found, "Container '\(name)' should appear in list after run")
        #expect(container.state == .running,
                "Container '\(name)' should be running, got \(container.state)")

        // --- 2. logs(id:lines:) does not throw ---
        let logOutput = try await runtime.logs(id: name, lines: 50)
        // logs may be empty for a sleep container — we only verify it doesn't throw
        _ = logOutput   // silence "result unused" warning

        // --- 3. inspect(id:) returns a string containing the container name ---
        let inspectOutput = try await runtime.inspect(id: name)
        #expect(inspectOutput.contains(name),
                "inspect output should contain the container name '\(name)'")

        // --- 4. stop(id:) ---
        try await runtime.stop(id: name)

        // Give the daemon a moment to update state.
        try await Task.sleep(for: .seconds(2))

        // --- 5. list shows the container with state != .running ---
        let containersAfterStop = try await runtime.listContainers()
        let stoppedContainer = containersAfterStop.first(where: { $0.id == name })
        let sc = try #require(stoppedContainer, "Container '\(name)' should still appear after stop")
        #expect(sc.state != .running,
                "Container '\(name)' should not be running after stop, got \(sc.state)")

        // --- 6. pruneContainers() ---
        try await runtime.pruneContainers()

        try await Task.sleep(for: .seconds(1))

        // --- 7. listContainers() no longer contains it ---
        let containersAfterPrune = try await runtime.listContainers()
        let stillPresent = containersAfterPrune.contains(where: { $0.id == name })
        #expect(!stillPresent, "Container '\(name)' should be gone after prune")
    }

    // MARK: - Test: Image list + inspect (read-only)

    /// Verifies that `listImages()` decodes without throwing and, when at least
    /// one image is present, that `inspectImage(reference:)` on the first element
    /// returns a non-empty string that contains that reference (or at least valid JSON).
    ///
    /// Destructive image operations (delete, prune) are intentionally **not** tested
    /// to avoid mutating the developer's real image store.
    @Test("listImages decodes without throwing; inspectImage returns non-empty JSON", .timeLimit(.minutes(1)))
    func imageListAndInspect() async throws {
        // --- 1. listImages() decodes without throwing ---
        let images = try await runtime.listImages()
        // A clean system may have zero images — that is still a valid decode.
        _ = images  // silence "result unused" warning

        // --- 2. inspectImage on the first element (when at least one image exists) ---
        if let first = images.first {
            let json = try await runtime.inspectImage(reference: first.reference)
            #expect(!json.isEmpty,
                    "inspectImage should return a non-empty string for '\(first.reference)'")
            // The raw JSON must at least contain the reference string we passed in,
            // or a well-known JSON marker confirming it is structured output.
            let looksLikeJSON = json.contains("{") && json.contains("}")
            #expect(looksLikeJSON,
                    "inspectImage output should look like JSON (contain '{' and '}') for '\(first.reference)'")
        }
    }

    // MARK: - Test 2: Kill + delete

    /// Creates a second scratch container, kills it (SIGKILL), verifies it is
    /// no longer running, then deletes it directly and verifies it is gone.
    @Test("Kill + delete: run → kill → list (not running) → delete → gone", .timeLimit(.minutes(2)))
    func killAndDelete() async throws {
        let name = uniqueContainerName(suffix: "2")

        // Teardown: forcibly delete the container even if the test fails.
        defer { runCLI(["delete", "--force", name]) }

        // --- Setup: create the container via the CLI directly ---
        let runCode = runCLI([
            "run", "-d", "--name", name,
            "alpine:latest", "sleep", "120",
        ])
        #expect(runCode == 0, "container run should succeed (exit 0), got \(runCode)")

        try await Task.sleep(for: .seconds(2))

        // Verify it's running before we kill it.
        let listBeforeKill = try await runtime.listContainers()
        let beforeKill = try #require(
            listBeforeKill.first(where: { $0.id == name }),
            "Container '\(name)' should appear in list before kill"
        )
        #expect(beforeKill.state == .running,
                "Container '\(name)' should be running before kill, got \(beforeKill.state)")

        // --- kill(id:) ---
        try await runtime.kill(id: name)

        try await Task.sleep(for: .seconds(2))

        // --- list shows not running ---
        let listAfterKill = try await runtime.listContainers()
        let afterKill = listAfterKill.first(where: { $0.id == name })
        let ak = try #require(afterKill, "Container '\(name)' should still appear after kill")
        #expect(ak.state != .running,
                "Container '\(name)' should not be running after kill, got \(ak.state)")

        // --- delete(id:) ---
        try await runtime.delete(id: name)

        try await Task.sleep(for: .seconds(1))

        // --- gone from list ---
        let listAfterDelete = try await runtime.listContainers()
        let stillPresent = listAfterDelete.contains(where: { $0.id == name })
        #expect(!stillPresent, "Container '\(name)' should be gone after delete")
    }
}
