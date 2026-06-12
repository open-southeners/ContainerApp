import Testing
import Foundation
@testable import ContainerApp

// MARK: - Fixture loader

private func loadComposeFixture(named name: String) throws -> (text: String, url: URL) {
    let bundle = Bundle(for: ComposeFixtureBundleLocator.self)
    // Fixtures are copied as a folder reference into the test bundle's Resources directory.
    if let url = bundle.url(forResource: name, withExtension: "yml", subdirectory: "Fixtures") {
        let text = try String(contentsOf: url, encoding: .utf8)
        return (text, url)
    }
    if let url = bundle.url(forResource: name, withExtension: "yml") {
        let text = try String(contentsOf: url, encoding: .utf8)
        return (text, url)
    }
    throw ComposeFixtureError.notFound(name: "\(name).yml")
}

private enum ComposeFixtureError: Error {
    case notFound(name: String)
}

private final class ComposeFixtureBundleLocator {}

// MARK: - Tests

@Suite("ComposeFileParser")
struct ComposeFileParserTests {

    // MARK: compose-named.yml

    @Test("compose-named.yml: projectName comes from top-level name: field")
    func namedFixtureProjectName() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.projectName == "myapp")
        #expect(project.displayName == "myapp")
    }

    @Test("compose-named.yml: services are listed in YAML declaration order")
    func namedFixtureServiceNames() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // Fixture declares: web, db, cache (in that order) — must be preserved,
        // not sorted alphabetically.
        #expect(project.serviceNames == ["web", "db", "cache"])
    }

    @Test("compose-named.yml: image refs are populated")
    func namedFixtureImageRefs() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.serviceImages["web"] == "nginx:latest")
        #expect(project.serviceImages["db"] == "postgres:16")
        #expect(project.serviceImages["cache"] == "redis:7")
    }

    @Test("container_name overrides are preserved per service")
    func containerNameOverridesPreserved() throws {
        let yaml = """
        name: localdev
        services:
          mysql:
            image: mysql:8
            container_name: local_mysql_server
          redis:
            image: redis:latest
        """
        let project = try ComposeFileParser.parse(
            text: yaml,
            fileURL: URL(fileURLWithPath: "/tmp/docker-compose.yml")
        )

        #expect(project.serviceContainerNames["mysql"] == "local_mysql_server")
        #expect(project.serviceContainerNames["redis"] == nil)
    }

    @Test("compose-named.yml: id equals standardized file path")
    func namedFixtureID() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.id == url.standardizedFileURL.path)
    }

    @Test("compose-named.yml: isMissing defaults to false")
    func namedFixtureNotMissing() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.isMissing == false)
    }

    // MARK: compose-unnamed.yml

    @Test("compose-unnamed.yml: projectName is derived from folder name")
    func unnamedFixtureProjectName() throws {
        let (text, url) = try loadComposeFixture(named: "compose-unnamed")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // Folder name contains the fixture path; projectName uses lastPathComponent.
        // The fixture lives inside the "Fixtures" folder — dots would be replaced,
        // but "Fixtures" has none, so it comes through verbatim.
        let expectedFolder = url.deletingLastPathComponent().lastPathComponent
        let expectedName = expectedFolder.replacingOccurrences(of: ".", with: "_")
        #expect(project.projectName == expectedName)
    }

    @Test("compose-unnamed.yml: null-body service is still listed")
    func unnamedFixtureNullBodyServiceListed() throws {
        let (text, url) = try loadComposeFixture(named: "compose-unnamed")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // Fixture declares: web (has image), cache (null body)
        #expect(project.serviceNames.contains("cache"))
        #expect(project.serviceNames.contains("web"))
    }

    @Test("compose-unnamed.yml: null-body service has no image entry")
    func unnamedFixtureNullBodyServiceNoImage() throws {
        let (text, url) = try loadComposeFixture(named: "compose-unnamed")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.serviceImages["cache"] == nil)
    }

    @Test("compose-unnamed.yml: ${TAG:-latest} image ref is preserved raw")
    func unnamedFixtureRawEnvVarPreserved() throws {
        let (text, url) = try loadComposeFixture(named: "compose-unnamed")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // The parser must not resolve ${TAG:-latest} — it must stay exactly as written.
        #expect(project.serviceImages["web"] == "myapp:${TAG:-latest}")
    }

    // MARK: Project-name sanitization pins

    @Test("projectName: dots in folder name are replaced with underscores")
    func projectNameDotReplacement() {
        let folderURL = URL(fileURLWithPath: "/Users/dev/projects/my.app", isDirectory: true)
        let name = ComposeFileParser.projectName(name: nil, folderURL: folderURL)

        #expect(name == "my_app")
    }

    @Test("projectName: name: field wins over folder-derived name")
    func projectNameFieldWins() {
        let folderURL = URL(fileURLWithPath: "/Users/dev/projects/my.app", isDirectory: true)
        let name = ComposeFileParser.projectName(name: "explicit-name", folderURL: folderURL)

        #expect(name == "explicit-name")
    }

    @Test("projectName: empty name: falls back to folder derivation")
    func projectNameEmptyStringFallsBack() {
        let folderURL = URL(fileURLWithPath: "/Users/dev/projects/my.app", isDirectory: true)
        let name = ComposeFileParser.projectName(name: "", folderURL: folderURL)

        #expect(name == "my_app")
    }

    // MARK: Error cases

    @Test("Garbage YAML throws parseFailed")
    func garbageYAMLThrowsParseFailed() throws {
        let garbage = "}{{{not yaml at all"
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        var caught: ComposeError?
        do {
            _ = try ComposeFileParser.parse(text: garbage, fileURL: url)
        } catch let error as ComposeError {
            caught = error
        } catch {}

        let error = try #require(caught)
        if case .parseFailed = error {
            // expected
        } else {
            Issue.record("Expected parseFailed but got \(error)")
        }
    }

    @Test("YAML without services: key throws parseFailed")
    func missingServicesKeyThrowsParseFailed() throws {
        let yaml = """
        name: noservices
        networks:
          default: {}
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        var caught: ComposeError?
        do {
            _ = try ComposeFileParser.parse(text: yaml, fileURL: url)
        } catch let error as ComposeError {
            caught = error
        } catch {}

        let error = try #require(caught)
        if case .parseFailed = error {
            // expected
        } else {
            Issue.record("Expected parseFailed but got \(error)")
        }
    }

    @Test("YAML with empty services: map parses without error")
    func emptyServicesMapParsesOK() throws {
        let yaml = """
        name: emptysvc
        services: {}
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        #expect(project.projectName == "emptysvc")
        #expect(project.serviceNames.isEmpty)
    }

    // MARK: YAML declaration order preservation

    @Test("Services retain YAML file order, not alphabetical order")
    func serviceOrderPreservedNonAlphabetical() throws {
        // Declare services in an order that differs from alphabetical:
        // zebra, apple, mango — alphabetical would be apple, mango, zebra.
        let yaml = """
        name: orderpins
        services:
          zebra:
            image: zebra:1
          apple:
            image: apple:1
          mango:
            image: mango:1
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        #expect(project.serviceNames == ["zebra", "apple", "mango"],
                "Service names must follow YAML declaration order, not alphabetical order")
    }

    // MARK: depends_on parsing

    @Test("depends_on: array form is parsed into serviceDependencies")
    func dependsOnArrayForm() throws {
        let yaml = """
        name: arraytest
        services:
          web:
            image: nginx:latest
            depends_on:
              - db
              - cache
          db:
            image: postgres:16
          cache:
            image: redis:7
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        let webDeps = try #require(project.serviceDependencies["web"])
        #expect(Set(webDeps) == Set(["db", "cache"]))
        #expect(project.serviceDependencies["db"] == nil)
        #expect(project.serviceDependencies["cache"] == nil)
    }

    @Test("depends_on: map form is parsed — keys only, condition ignored")
    func dependsOnMapForm() throws {
        let yaml = """
        name: maptest
        services:
          web:
            image: nginx:latest
            depends_on:
              db:
                condition: service_healthy
              cache:
                condition: service_started
          db:
            image: postgres:16
          cache:
            image: redis:7
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        let webDeps = try #require(project.serviceDependencies["web"])
        #expect(Set(webDeps) == Set(["db", "cache"]))
    }

    @Test("depends_on: map form with mixed value types (string + bool) parses correctly")
    func dependsOnMapFormMixedValueTypes() throws {
        // Real compose files can include `restart: true` (a Bool) alongside
        // `condition: service_healthy` (a String) in the same condition object.
        // Previously this caused a decode failure because the map was typed as
        // [String: [String: String]].  The fix uses IgnoredValue to skip values.
        let yaml = """
        name: mixedtest
        services:
          web:
            image: nginx:latest
            depends_on:
              db:
                condition: service_healthy
                restart: true
              cache:
                condition: service_started
          db:
            image: postgres:16
          cache:
            image: redis:7
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        // Dependency names must be extracted from the map keys regardless of value types.
        let webDeps = try #require(project.serviceDependencies["web"])
        #expect(Set(webDeps) == Set(["db", "cache"]))
        // Other fields must still parse normally.
        #expect(project.projectName == "mixedtest")
        #expect(project.serviceImages["web"] == "nginx:latest")
        #expect(project.serviceImages["db"] == "postgres:16")
        #expect(project.serviceImages["cache"] == "redis:7")
        #expect(project.serviceDependencies["db"] == nil)
        #expect(project.serviceDependencies["cache"] == nil)
    }

    @Test("depends_on: absent — service has no entry in serviceDependencies")
    func dependsOnAbsent() throws {
        let yaml = """
        name: nodeps
        services:
          web:
            image: nginx:latest
          db:
            image: postgres:16
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        #expect(project.serviceDependencies.isEmpty)
    }

    @Test("depends_on: unknown service reference does not crash parsing")
    func dependsOnUnknownServiceReference() throws {
        let yaml = """
        name: unknown
        services:
          web:
            image: nginx:latest
            depends_on:
              - nonexistent
        """
        let url = URL(fileURLWithPath: "/tmp/docker-compose.yml")
        let project = try ComposeFileParser.parse(text: yaml, fileURL: url)

        // The dependency is stored as declared; stopOrder filters unknown refs.
        let webDeps = try #require(project.serviceDependencies["web"])
        #expect(webDeps == ["nonexistent"])
    }

    // MARK: stopOrder

    @Test("stopOrder: simple chain — dependent before dependency")
    func stopOrderSimpleChain() {
        // web depends on db → stop web before db
        let order = ComposeFileParser.stopOrder(
            serviceNames: ["web", "db"],
            dependencies: ["web": ["db"]]
        )
        #expect(order == ["web", "db"])
    }

    @Test("stopOrder: diamond — a depends on b and c, both depend on d")
    func stopOrderDiamond() {
        // a → b → d
        //   → c → d
        // safe stop: a first, then b and c (order between them is reverse-file-order),
        // then d last.
        let order = ComposeFileParser.stopOrder(
            serviceNames: ["a", "b", "c", "d"],
            dependencies: ["a": ["b", "c"], "b": ["d"], "c": ["d"]]
        )
        // a must be first; d must be last; b and c must both precede d.
        #expect(order.first == "a", "a must be stopped first")
        #expect(order.last == "d", "d must be stopped last")
        #expect(order.contains("b"))
        #expect(order.contains("c"))
        #expect(order.count == 4)
        // b and c both precede d
        let bIndex = try? #require(order.firstIndex(of: "b"))
        let cIndex = try? #require(order.firstIndex(of: "c"))
        let dIndex = try? #require(order.firstIndex(of: "d"))
        if let bIndex, let dIndex { #expect(bIndex < dIndex) }
        if let cIndex, let dIndex { #expect(cIndex < dIndex) }
    }

    @Test("stopOrder: no deps — reverse YAML file order")
    func stopOrderNoDeps() {
        let order = ComposeFileParser.stopOrder(
            serviceNames: ["web", "db", "cache"],
            dependencies: [:]
        )
        // No dependencies: reverse file order (cache, db, web).
        #expect(order == ["cache", "db", "web"])
    }

    @Test("stopOrder: cycle — terminates and covers all services")
    func stopOrderCycle() {
        // a depends on b, b depends on a — a cycle.
        let order = ComposeFileParser.stopOrder(
            serviceNames: ["a", "b"],
            dependencies: ["a": ["b"], "b": ["a"]]
        )
        // Must not hang; must include both services exactly once.
        #expect(order.count == 2)
        #expect(Set(order) == Set(["a", "b"]))
    }

    @Test("stopOrder: cycle is deterministic across calls")
    func stopOrderCycleDeterministic() {
        let deps: [String: [String]] = ["a": ["b"], "b": ["a"]]
        let names = ["a", "b"]
        let first  = ComposeFileParser.stopOrder(serviceNames: names, dependencies: deps)
        let second = ComposeFileParser.stopOrder(serviceNames: names, dependencies: deps)
        #expect(first == second, "stopOrder must be deterministic")
    }

    @Test("stopOrder: unknown dependency names are ignored in ordering")
    func stopOrderIgnoresUnknownDeps() {
        // "nonexistent" is not in serviceNames — should be silently dropped.
        let order = ComposeFileParser.stopOrder(
            serviceNames: ["web", "db"],
            dependencies: ["web": ["nonexistent", "db"]]
        )
        // web depends on db (known), so web before db; nonexistent is ignored.
        #expect(order == ["web", "db"])
    }

    @Test("stopOrder: compose-named.yml fixture deps produce correct order")
    func stopOrderNamedFixture() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // Fixture: web depends_on db; cache has no deps.
        // File order: web, db, cache.
        // Expected stop order: web first (depends on db), then db and cache
        // in reverse file order among themselves → cache before db (but web stops first).
        // Actually: web is the only dependent; db and cache have in-degree 0 from web's
        // perspective after web is removed.  cache is declared after db, so reverse order
        // puts cache before db.
        let order = ComposeFileParser.stopOrder(
            serviceNames: project.serviceNames,
            dependencies: project.serviceDependencies
        )

        #expect(order.count == 3)
        let webIndex = try #require(order.firstIndex(of: "web"))
        let dbIndex  = try #require(order.firstIndex(of: "db"))
        #expect(webIndex < dbIndex, "web must stop before db (web depends_on db)")
    }
}
