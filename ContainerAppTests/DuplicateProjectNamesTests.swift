import Testing
import Foundation
@testable import ContainerApp

// MARK: - Helpers

/// Builds a minimal `ComposeProject` for duplicate-detection tests.
/// Uses a unique id suffix so two projects can have the same `projectName` without
/// sharing an `id` (ids are paths and must be distinct for `Identifiable`).
private func makeProject(
    id: String,
    projectName: String,
    isMissing: Bool = false
) -> ComposeProject {
    var project = ComposeProject(
        id: id,
        fileURL: URL(fileURLWithPath: id),
        projectName: projectName,
        displayName: projectName,
        serviceNames: [],
        serviceImages: [:]
    )
    project.isMissing = isMissing
    return project
}

// MARK: - Tests

@Suite("ContainersViewModel detectDuplicateProjectNames")
struct DuplicateProjectNamesTests {

    // MARK: No duplicates

    @Test("Empty project list returns empty set")
    func emptyListReturnsEmptySet() {
        let result = ContainersViewModel.detectDuplicateProjectNames([])
        #expect(result.isEmpty)
    }

    @Test("Single project with unique name returns empty set")
    func singleUniqueProjectReturnsEmptySet() {
        let projects = [
            makeProject(id: "/a/compose.yml", projectName: "alpha"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result.isEmpty)
    }

    @Test("Multiple projects with distinct names returns empty set")
    func distinctNamesReturnEmptySet() {
        let projects = [
            makeProject(id: "/a/compose.yml", projectName: "alpha"),
            makeProject(id: "/b/compose.yml", projectName: "beta"),
            makeProject(id: "/c/compose.yml", projectName: "gamma"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result.isEmpty)
    }

    // MARK: Two projects sharing a name

    @Test("Two non-missing projects sharing the same name returns that name")
    func twoProjectsSameNameReturnsName() {
        let projects = [
            makeProject(id: "/dir1/compose.yml", projectName: "myapp"),
            makeProject(id: "/dir2/compose.yml", projectName: "myapp"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result == ["myapp"])
    }

    // MARK: Missing projects excluded

    @Test("Missing project is excluded — does not form a duplicate pair")
    func missingProjectExcluded() {
        // One non-missing and one missing project with the same name.
        // The missing one doesn't produce containers, so no collision risk.
        let projects = [
            makeProject(id: "/dir1/compose.yml", projectName: "myapp"),
            makeProject(id: "/dir2/compose.yml", projectName: "myapp", isMissing: true),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result.isEmpty)
    }

    @Test("Two missing projects with the same name do not form a duplicate")
    func twoMissingProjectsNotDuplicate() {
        let projects = [
            makeProject(id: "/dir1/compose.yml", projectName: "myapp", isMissing: true),
            makeProject(id: "/dir2/compose.yml", projectName: "myapp", isMissing: true),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result.isEmpty)
    }

    // MARK: Three-way duplicate

    @Test("Three projects sharing the same name — name appears in result once")
    func threeProjectsSameName() {
        let projects = [
            makeProject(id: "/a/compose.yml", projectName: "clash"),
            makeProject(id: "/b/compose.yml", projectName: "clash"),
            makeProject(id: "/c/compose.yml", projectName: "clash"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result == ["clash"])
    }

    // MARK: Mixed: some duplicate, some not

    @Test("Only the duplicated name is returned when other projects have unique names")
    func mixedDuplicateAndUnique() {
        let projects = [
            makeProject(id: "/a/compose.yml", projectName: "alpha"),
            makeProject(id: "/b/compose.yml", projectName: "beta"),
            makeProject(id: "/c/compose.yml", projectName: "beta"),
            makeProject(id: "/d/compose.yml", projectName: "gamma"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result == ["beta"])
    }

    @Test("Multiple duplicate groups are all included in the result")
    func multipleDuplicateGroups() {
        let projects = [
            makeProject(id: "/a1/compose.yml", projectName: "alpha"),
            makeProject(id: "/a2/compose.yml", projectName: "alpha"),
            makeProject(id: "/b1/compose.yml", projectName: "beta"),
            makeProject(id: "/b2/compose.yml", projectName: "beta"),
        ]
        let result = ContainersViewModel.detectDuplicateProjectNames(projects)
        #expect(result == ["alpha", "beta"])
    }
}
