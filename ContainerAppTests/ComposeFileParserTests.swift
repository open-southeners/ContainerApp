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

    @Test("compose-named.yml: services are listed (alphabetically sorted)")
    func namedFixtureServiceNames() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        // Fixture declares: web, db — sorted alphabetically: db, web
        #expect(project.serviceNames == ["db", "web"])
    }

    @Test("compose-named.yml: image refs are populated")
    func namedFixtureImageRefs() throws {
        let (text, url) = try loadComposeFixture(named: "compose-named")
        let project = try ComposeFileParser.parse(text: text, fileURL: url)

        #expect(project.serviceImages["web"] == "nginx:latest")
        #expect(project.serviceImages["db"] == "postgres:16")
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
}
