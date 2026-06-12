import Testing
import Foundation
@testable import ContainerApp

// MARK: - Helpers

/// Builds a minimal `ComposeProject` for a given project name and service list.
private func makeProject(
    projectName: String,
    serviceNames: [String],
    serviceImages: [String: String] = [:]
) -> ComposeProject {
    ComposeProject(
        id: "/tmp/\(projectName)/compose.yml",
        fileURL: URL(fileURLWithPath: "/tmp/\(projectName)/compose.yml"),
        projectName: projectName,
        displayName: projectName,
        serviceNames: serviceNames,
        serviceImages: serviceImages
    )
}

/// Builds a minimal `ContainerSummary` with just `id` and `state` set.
private func makeContainer(id: String, state: ContainerState) -> ContainerSummary {
    ContainerSummary(
        id: id,
        name: id,
        image: "test-image:latest",
        state: state,
        status: nil,
        command: nil,
        createdAt: nil,
        startedAt: nil,
        ports: nil,
        cpuText: nil,
        memoryText: nil,
        imageReference: nil
    )
}

// MARK: - Tests

@Suite("ContainersViewModel serviceStatuses")
struct ComposeStatusTests {

    // MARK: Exact-match only

    @Test("Project 'web' does NOT claim container 'web-app-cache' from another project")
    func exactMatchOnlyNoPrefixClaim() {
        // A project named "web" with service "app" expects container "web-app".
        // A container named "web-app-cache" (a different project's container) must NOT match.
        let project = makeProject(projectName: "web", serviceNames: ["app"])
        let containers = [
            makeContainer(id: "web-app", state: .running),
            makeContainer(id: "web-app-cache", state: .running),
        ]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        #expect(statuses.count == 1)
        let status = statuses[0]
        #expect(status.id == "web-app")
        #expect(status.state == .running)
    }

    @Test("Project 'web' does NOT claim container 'web-db' from another project")
    func noPrefixClaimForUnregisteredService() {
        // project "web" has services ["api"]; container "web-db" belongs to another project.
        let project = makeProject(projectName: "web", serviceNames: ["api"])
        let containers = [
            makeContainer(id: "web-api", state: .running),
            makeContainer(id: "web-db", state: .running),  // different project's container
        ]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        #expect(statuses.count == 1)
        #expect(statuses[0].id == "web-api")
        #expect(statuses[0].state == .running)
    }

    // MARK: Running / stopped / missing mix

    @Test("Mixed running, stopped, and missing services are all represented")
    func mixedRunningStoppedMissing() throws {
        let project = makeProject(
            projectName: "myapp",
            serviceNames: ["web", "db", "cache"]
        )
        let containers = [
            makeContainer(id: "myapp-web", state: .running),
            makeContainer(id: "myapp-db", state: .stopped),
            // "myapp-cache" is absent — not yet created
        ]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        #expect(statuses.count == 3)

        let web = try #require(statuses.first { $0.serviceName == "web" })
        #expect(web.id == "myapp-web")
        #expect(web.state == .running)

        let db = try #require(statuses.first { $0.serviceName == "db" })
        #expect(db.id == "myapp-db")
        #expect(db.state == .stopped)

        let cache = try #require(statuses.first { $0.serviceName == "cache" })
        #expect(cache.id == "myapp-cache")
        #expect(cache.state == nil, "Missing container should have nil state")
    }

    // MARK: Empty containers

    @Test("All services get nil state when no containers exist")
    func emptyContainersAllNilState() {
        let project = makeProject(
            projectName: "demo",
            serviceNames: ["frontend", "backend"]
        )

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: [])

        #expect(statuses.count == 2)
        #expect(statuses.allSatisfy { $0.state == nil })
    }

    @Test("Empty service list produces empty statuses")
    func emptyServiceListProducesEmptyStatuses() {
        let project = makeProject(projectName: "empty", serviceNames: [])
        let containers = [makeContainer(id: "empty-web", state: .running)]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        #expect(statuses.isEmpty)
    }

    // MARK: Image passthrough

    @Test("Image from serviceImages is passed through to the status")
    func imagePassthrough() throws {
        let project = makeProject(
            projectName: "proj",
            serviceNames: ["svc"],
            serviceImages: ["svc": "nginx:${TAG:-latest}"]
        )

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: [])

        let status = try #require(statuses.first)
        #expect(status.image == "nginx:${TAG:-latest}")
    }

    @Test("Service with no image entry produces nil image in status")
    func noImageEntryProducesNilImage() throws {
        let project = makeProject(
            projectName: "proj",
            serviceNames: ["svc"],
            serviceImages: [:]  // no entry for "svc"
        )

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: [])

        let status = try #require(statuses.first)
        #expect(status.image == nil)
    }

    // MARK: Service id construction

    @Test("Container id is exactly '<projectName>-<serviceName>'")
    func containerIDConstruction() throws {
        let project = makeProject(projectName: "my_app", serviceNames: ["worker"])

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: [])

        let status = try #require(statuses.first)
        #expect(status.id == "my_app-worker")
    }

    // MARK: Exited state is preserved

    @Test("Exited state is propagated correctly (not confused with nil)")
    func exitedStatePreserved() throws {
        let project = makeProject(projectName: "demo", serviceNames: ["migrator"])
        let containers = [makeContainer(id: "demo-migrator", state: .exited)]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        let status = try #require(statuses.first)
        #expect(status.state == .exited)
    }

    // MARK: Multiple projects' containers don't collide

    @Test("Containers from a different project with same service name do not match")
    func differentProjectNoCollision() throws {
        // Project "alpha" has service "web"; project "beta" also has service "web".
        // Only "alpha-web" should match for project "alpha".
        let project = makeProject(projectName: "alpha", serviceNames: ["web"])
        let containers = [
            makeContainer(id: "alpha-web", state: .running),
            makeContainer(id: "beta-web", state: .running),
        ]

        let statuses = ContainersViewModel.serviceStatuses(for: project, containers: containers)

        let status = try #require(statuses.first)
        #expect(status.id == "alpha-web")
        #expect(status.state == .running)
        #expect(statuses.count == 1)
    }
}
