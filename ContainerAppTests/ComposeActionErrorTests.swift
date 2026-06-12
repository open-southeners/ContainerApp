import Testing
import Foundation
@testable import ContainerApp

// MARK: - Helpers

/// Builds a minimal `ComposeProject` for a given project name and service list.
private func makeProject(
    projectName: String,
    serviceNames: [String] = ["web"]
) -> ComposeProject {
    ComposeProject(
        id: "/tmp/\(projectName)/compose.yml",
        fileURL: URL(fileURLWithPath: "/tmp/\(projectName)/compose.yml"),
        projectName: projectName,
        displayName: projectName,
        serviceNames: serviceNames,
        serviceImages: [:]
    )
}

// MARK: - Test suite

/// Regression tests for the error-visibility ordering in compose actions.
///
/// The invariant: when a compose action fails, the `errorMessage` set by `handle(_:)`
/// must survive the subsequent quiet refresh.  Before the fix, `downProject` and
/// `downService` called `handle(error)` first and then `refresh(quiet: true)`, which
/// cleared `errorMessage` on the refresh's success path.
@MainActor
@Suite("ComposeAction error-visibility regression")
struct ComposeActionErrorTests {

    // MARK: upProject failure surfaces errorMessage

    @Test("upProject failure sets errorMessage and stores stderr in lastComposeOutput")
    func upProjectFailureSetsErrorMessage() async {
        let containerRuntime = MockContainerRuntime()
        let composeRuntime = MockComposeRuntime(
            containerRuntime: containerRuntime,
            failNextUp: .commandFailed(exitCode: 1, stderr: "mock failure")
        )
        let vm = ContainersViewModel(
            runtime: containerRuntime,
            composeRuntime: composeRuntime
        )

        let project = makeProject(projectName: "testapp")
        let task = vm.upProject(project)
        await task.value

        #expect(vm.errorMessage != nil, "errorMessage must be non-nil after a failed upProject")
        #expect(
            vm.lastComposeOutput == "mock failure",
            "lastComposeOutput should contain the stderr from the failed command"
        )
        #expect(
            !vm.busyComposeProjects.contains(project.id),
            "project must be removed from busyComposeProjects after the action completes"
        )
    }

    // MARK: downProject failure surfaces errorMessage

    @Test("downProject stop failure sets errorMessage and clears busy flag")
    func downProjectStopFailureSetsErrorMessage() async {
        let containerRuntime = FailingStopMockRuntime()
        let composeRuntime = MockComposeRuntime()
        let vm = ContainersViewModel(
            runtime: containerRuntime,
            composeRuntime: composeRuntime
        )

        // Seed one running container so downProject has something to stop.
        let project = makeProject(projectName: "myproj", serviceNames: ["svc"])
        vm.containers = [
            ContainerSummary(
                id: "myproj-svc",
                name: "myproj-svc",
                image: "nginx:latest",
                state: .running,
                status: "Up",
                command: nil,
                createdAt: nil,
                startedAt: nil,
                ports: nil,
                cpuText: nil,
                memoryText: nil,
                imageReference: nil
            ),
        ]

        let task = vm.downProject(project)
        await task.value

        #expect(vm.errorMessage != nil, "errorMessage must be non-nil after a failed stop")
        #expect(
            !vm.busyComposeProjects.contains(project.id),
            "project must be removed from busyComposeProjects after the action completes"
        )
    }

    // MARK: downService failure surfaces errorMessage

    @Test("downService stop failure sets errorMessage and clears busy flag")
    func downServiceStopFailureSetsErrorMessage() async {
        let containerRuntime = FailingStopMockRuntime()
        let composeRuntime = MockComposeRuntime()
        let vm = ContainersViewModel(
            runtime: containerRuntime,
            composeRuntime: composeRuntime
        )

        let project = makeProject(projectName: "myproj", serviceNames: ["svc"])
        vm.containers = [
            ContainerSummary(
                id: "myproj-svc",
                name: "myproj-svc",
                image: "nginx:latest",
                state: .running,
                status: "Up",
                command: nil,
                createdAt: nil,
                startedAt: nil,
                ports: nil,
                cpuText: nil,
                memoryText: nil,
                imageReference: nil
            ),
        ]

        let task = vm.downService("svc", in: project)
        await task.value

        #expect(vm.errorMessage != nil, "errorMessage must be non-nil after a failed stop")
        #expect(
            !vm.busyComposeProjects.contains(project.id),
            "project must be removed from busyComposeProjects after the action completes"
        )
    }

    // MARK: upProject success clears errorMessage

    @Test("upProject success clears errorMessage and populates lastComposeOutput")
    func upProjectSuccessClearsErrorMessage() async {
        let containerRuntime = MockContainerRuntime()
        let composeRuntime = MockComposeRuntime(containerRuntime: containerRuntime)
        let vm = ContainersViewModel(
            runtime: containerRuntime,
            composeRuntime: composeRuntime
        )
        // Pre-set an error so we can confirm it is cleared.
        vm.errorMessage = "stale error"

        let project = makeProject(projectName: "successapp")
        let task = vm.upProject(project)
        await task.value

        #expect(vm.errorMessage == nil, "errorMessage must be nil after a successful upProject")
        #expect(
            vm.lastComposeOutput != nil,
            "lastComposeOutput should be non-nil after a successful upProject"
        )
        #expect(
            !vm.busyComposeProjects.contains(project.id),
            "project must be removed from busyComposeProjects after the action completes"
        )
    }

    @Test("upProject publishes progress before the action completes")
    func upProjectPublishesLiveProgress() async {
        let containerRuntime = MockContainerRuntime()
        let composeRuntime = MockComposeRuntime(containerRuntime: containerRuntime)
        let vm = ContainersViewModel(
            runtime: containerRuntime,
            composeRuntime: composeRuntime
        )

        let project = makeProject(projectName: "progressapp")
        let task = vm.upProject(project)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.busyComposeProjects.contains(project.id))
        #expect(vm.lastComposeOutput == "Resolving services…")

        await task.value
    }
}

// MARK: - FailingStopMockRuntime

/// A minimal `ContainerRuntime` stub whose `stop` always throws `.commandFailed`.
/// All other methods delegate to a real `MockContainerRuntime` so `refresh` can
/// complete without errors.
private final class FailingStopMockRuntime: ContainerRuntime {

    private let inner = MockContainerRuntime()

    func listContainers() async throws -> [ContainerSummary] {
        try await inner.listContainers()
    }

    func inspect(id: String) async throws -> String {
        try await inner.inspect(id: id)
    }

    func logs(id: String, lines: Int) async throws -> String {
        try await inner.logs(id: id, lines: lines)
    }

    func stats(id: String?) async throws -> [ContainerStats] {
        try await inner.stats(id: id)
    }

    func start(id: String) async throws {
        try await inner.start(id: id)
    }

    func stop(id: String) async throws {
        // Always fail — this is the failure mode under test.
        throw ContainerRuntimeError.commandFailed(exitCode: 1, stderr: "stop failed (mock)")
    }

    func kill(id: String) async throws {
        try await inner.kill(id: id)
    }

    func delete(id: String) async throws {
        try await inner.delete(id: id)
    }

    func pruneContainers() async throws {
        try await inner.pruneContainers()
    }

    func startSystem() async throws {
        try await inner.startSystem()
    }

    func stopSystem() async throws {
        try await inner.stopSystem()
    }

    func systemStatus() async throws -> ContainerSystemStatus {
        try await inner.systemStatus()
    }

    func listImages() async throws -> [ImageSummary] {
        try await inner.listImages()
    }

    func inspectImage(reference: String) async throws -> String {
        try await inner.inspectImage(reference: reference)
    }

    func deleteImage(reference: String) async throws {
        try await inner.deleteImage(reference: reference)
    }

    func pruneImages() async throws -> String {
        try await inner.pruneImages()
    }
}
