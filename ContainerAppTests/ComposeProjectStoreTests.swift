import Testing
import Foundation
@testable import ContainerApp

// MARK: - Tests

@Suite("ComposeProjectStore")
struct ComposeProjectStoreTests {

    /// Each test gets a fresh store backed by a suite-named `UserDefaults` instance.
    /// The suite domain is cleared during init so no previous test's data leaks through.
    private let store: ComposeProjectStore

    init() {
        let suiteName = "com.opensoutheners.ContainerAppTests.ComposeProjectStoreTests"
        // Wipe any leftover state from previous runs.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        store = ComposeProjectStore(defaults: defaults)
    }

    // MARK: Empty state

    @Test("paths() returns empty array when nothing is registered")
    func emptyInitialState() {
        #expect(store.paths().isEmpty)
    }

    // MARK: Round-trip

    @Test("add and paths: registered path is returned")
    func addAndRetrieve() {
        let url = URL(fileURLWithPath: "/projects/myapp/docker-compose.yml")
        store.add(url)

        let paths = store.paths()
        #expect(paths.count == 1)
        #expect(paths.first == url.standardizedFileURL.path)
    }

    @Test("add multiple paths: all are returned in registration order")
    func addMultiplePaths() {
        let url1 = URL(fileURLWithPath: "/projects/alpha/docker-compose.yml")
        let url2 = URL(fileURLWithPath: "/projects/beta/docker-compose.yml")
        store.add(url1)
        store.add(url2)

        let paths = store.paths()
        #expect(paths.count == 2)
        #expect(paths[0] == url1.standardizedFileURL.path)
        #expect(paths[1] == url2.standardizedFileURL.path)
    }

    // MARK: Deduplication

    @Test("add: adding the same URL twice is a no-op")
    func addDeduplicatesSameURL() {
        let url = URL(fileURLWithPath: "/projects/myapp/docker-compose.yml")
        store.add(url)
        store.add(url)

        #expect(store.paths().count == 1)
    }

    @Test("add: adding equivalent standardized paths deduplicates")
    func addDeduplicatesEquivalentPaths() {
        // Both represent the same path after standardization.
        let url1 = URL(fileURLWithPath: "/projects/myapp/./docker-compose.yml")
        let url2 = URL(fileURLWithPath: "/projects/myapp/docker-compose.yml")
        store.add(url1)
        store.add(url2)

        #expect(store.paths().count == 1)
    }

    // MARK: Remove

    @Test("remove: registered path is no longer returned")
    func removeExistingPath() {
        let url = URL(fileURLWithPath: "/projects/myapp/docker-compose.yml")
        store.add(url)
        #expect(store.paths().count == 1)

        store.remove(id: url.standardizedFileURL.path)
        #expect(store.paths().isEmpty)
    }

    @Test("remove: removing an id that was never registered is a no-op")
    func removeUnknownIDIsNoOp() {
        let url = URL(fileURLWithPath: "/projects/myapp/docker-compose.yml")
        store.add(url)

        store.remove(id: "/projects/other/docker-compose.yml")
        #expect(store.paths().count == 1)
    }

    @Test("remove: only the matching path is removed; others remain")
    func removeOnlyMatchingPath() {
        let url1 = URL(fileURLWithPath: "/projects/alpha/docker-compose.yml")
        let url2 = URL(fileURLWithPath: "/projects/beta/docker-compose.yml")
        store.add(url1)
        store.add(url2)

        store.remove(id: url1.standardizedFileURL.path)

        let paths = store.paths()
        #expect(paths.count == 1)
        #expect(paths.first == url2.standardizedFileURL.path)
    }
}
