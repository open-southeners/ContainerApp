import Testing
import Foundation
@testable import ContainerApp

// MARK: - Fixture loader

private func loadFixture(named name: String, extension ext: String = "json") throws -> String {
    let bundle = Bundle(for: FixtureBundleLocator.self)
    // Fixtures are copied as a folder reference, so they live in a "Fixtures" subdirectory
    // inside the test bundle's Resources directory.
    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") {
        return try String(contentsOf: url, encoding: .utf8)
    }
    // Fallback: flat lookup (no subdirectory) for alternative bundle layouts
    if let url = bundle.url(forResource: name, withExtension: ext) {
        return try String(contentsOf: url, encoding: .utf8)
    }
    throw FixtureError.notFound(name: "\(name).\(ext)")
}

private enum FixtureError: Error {
    case notFound(name: String)
}

/// A concrete class whose bundle contains the Fixtures resources.
private final class FixtureBundleLocator {}

// MARK: - Tests

@Suite("FlexibleContainerDecoder")
struct ContainerCLIModelsTests {

    // MARK: list-all.json (running container)

    @Test("Decodes list-all.json: one running container")
    func decodeListAllRunning() throws {
        let json = try loadFixture(named: "list-all")
        let containers = try FlexibleContainerDecoder.decodeList(from: json)

        #expect(containers.count == 1)

        let c = try #require(containers.first)
        #expect(c.id == "plan-test")
        #expect(c.name == "plan-test")          // name == id (no separate name in CLI)
        #expect(c.state == .running)
        #expect(c.image == "alpine:latest")     // docker.io/library/ prefix stripped
        #expect(c.createdAt != nil)
        #expect(c.startedAt != nil)
        #expect(c.command == "sleep 600")
    }

    // MARK: list-all-stopped.json (stopped container)

    @Test("Decodes list-all-stopped.json: stopped state, startedAt retained")
    func decodeListAllStopped() throws {
        let json = try loadFixture(named: "list-all-stopped")
        let containers = try FlexibleContainerDecoder.decodeList(from: json)

        #expect(containers.count == 1)

        let c = try #require(containers.first)
        #expect(c.state == .stopped)
        // startedDate is retained in the fixture after stopping
        #expect(c.startedAt != nil)
    }

    // MARK: stats.json

    @Test("Decodes stats.json: memory/network/blockIO texts, cpuPercent nil")
    func decodeStats() throws {
        let json = try loadFixture(named: "stats")
        let stats = try FlexibleContainerDecoder.decodeStats(from: json)

        #expect(stats.count == 1)

        let s = try #require(stats.first)
        #expect(s.id == "plan-test")

        // cpuUsageUsec is cumulative — percentage needs two samples, left nil until Phase 4
        #expect(s.cpuPercent == nil)

        // memoryText should be non-nil and contain "/" (usage / limit format)
        let memText = try #require(s.memoryText)
        #expect(memText.contains("/"))

        // network and block I/O texts should be non-nil
        #expect(s.networkText != nil)
        #expect(s.blockIOText != nil)
    }

    // MARK: list-all-ports.json (ports mapping)

    @Test("Decodes list-all-ports.json: ports mapped to 'hostPort->containerPort/proto'")
    func decodeListAllPorts() throws {
        let json = try loadFixture(named: "list-all-ports")
        let containers = try FlexibleContainerDecoder.decodeList(from: json)

        #expect(containers.count == 1)

        let c = try #require(containers.first)
        #expect(c.id == "ports-test")
        #expect(c.state == .running)

        // hostAddress is "0.0.0.0" → omitted; expected format: "8080->80/tcp"
        let ports = try #require(c.ports)
        #expect(ports == "8080->80/tcp")
    }

    // MARK: Malformed input

    @Test("Malformed input throws decodingFailed")
    func malformedInputThrows() throws {
        let badJSON = "not json"
        var caught: ContainerRuntimeError?
        do {
            _ = try FlexibleContainerDecoder.decodeList(from: badJSON)
        } catch let error as ContainerRuntimeError {
            caught = error
        }
        let error = try #require(caught)
        if case .decodingFailed = error {
            // expected
        } else {
            Issue.record("Expected decodingFailed but got \(error)")
        }
    }
}
