import Foundation

// MARK: - MockComposeRuntime

/// A canned `ComposeRuntime` implementation for SwiftUI previews and unit tests.
///
/// `up` creates-or-starts containers named `<project.projectName>-<service>` in the
/// shared `MockStore` (accessed via the `MockContainerRuntime`'s exposed `store`
/// property), so the Compose section and the container list show consistent state in
/// previews without any pre-seeding.
final class MockComposeRuntime: ComposeRuntime {

    /// Direct reference to the shared mock store.  When provided, `up` and `down`
    /// mutate the store directly so compose-managed containers appear in the container
    /// list immediately after the action completes.
    private let mockStore: MockStore?

    /// Convenience init that accepts a `MockContainerRuntime` (the most common call site).
    /// Pass `nil` when a no-op mock is sufficient.
    init(containerRuntime: MockContainerRuntime? = nil) {
        self.mockStore = containerRuntime?.store
    }

    // MARK: - ComposeRuntime

    /// Creates (or starts) the containers for every resolved service in `project`.
    ///
    /// For each `<project.projectName>-<service>` id, the container is inserted into
    /// the mock store with `.running` state if it does not already exist, or
    /// transitioned to `.running` if it was previously stopped/exited.
    func up(project: ComposeProject, services: [String], rebuild: Bool, noCache: Bool) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))

        // Determine which service names to bring up.
        let serviceList = services.isEmpty ? project.serviceNames : services

        if let store = mockStore {
            for serviceName in serviceList {
                let containerID = "\(project.projectName)-\(serviceName)"
                let container = ContainerSummary(
                    id: containerID,
                    name: containerID,
                    image: project.serviceImages[serviceName] ?? "unknown",
                    state: .running,
                    status: "Up Less than a second",
                    command: nil,
                    createdAt: Date(),
                    startedAt: Date(),
                    ports: nil,
                    cpuText: nil,
                    memoryText: nil,
                    imageReference: project.serviceImages[serviceName]
                )
                // `add` replaces an existing container with the same id (handles restart).
                await store.add(container)
            }
        }

        // Return a canned output resembling real container-compose up -d output.
        let containerIDs = serviceList.map { "\(project.projectName)-\($0)" }
        let lines = containerIDs.map { "\($0): started" }.joined(separator: "\n")
        return lines.isEmpty ? "No services to start." : lines
    }

    /// Returns a canned build success line.
    func build(project: ComposeProject, services: [String], noCache: Bool) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return "Build complete (mock)."
    }

    /// Returns the mock version string — never nil (binary is always "present" in mock mode).
    func version() async -> String? {
        return "container-compose version 0.12.0 (mock)"
    }
}
