import ContainerizationError
import ContainerResource
import Foundation
import Testing
@testable import ContainerApp

// MARK: - Container and stats mapping

@Suite("Container API model mapping")
struct ContainerAPIModelsTests {

    // MARK: list-all.json (running container)

    @Test("Maps list-all.json: one running container")
    func mapListAllRunning() throws {
        let containers = try decodeFixture([ManagedContainer].self, named: "list-all")
            .map { $0.toContainerSummary() }

        #expect(containers.count == 1)

        let c = try #require(containers.first)
        #expect(c.id == "plan-test")
        #expect(c.name == "plan-test")          // name == id (no separate name field)
        #expect(c.state == .running)
        #expect(c.image == "alpine:latest")     // docker.io/library/ prefix stripped
        #expect(c.imageReference == "docker.io/library/alpine:latest")  // raw, unstripped
        #expect(c.createdAt != nil)
        #expect(c.startedAt != nil)
        #expect(c.command == "sleep 600")
        #expect(c.ports == nil)
    }

    // MARK: list-all-stopped.json (stopped container)

    @Test("Maps list-all-stopped.json: stopped state, startedAt retained")
    func mapListAllStopped() throws {
        let containers = try decodeFixture([ManagedContainer].self, named: "list-all-stopped")
            .map { $0.toContainerSummary() }

        #expect(containers.count == 1)

        let c = try #require(containers.first)
        #expect(c.state == .stopped)
        // startedDate is retained in the fixture after stopping
        #expect(c.startedAt != nil)
    }

    // MARK: list-all-ports.json (ports mapping)

    @Test("Maps list-all-ports.json: ports as 'hostPort->containerPort/proto'")
    func mapListAllPorts() throws {
        let containers = try decodeFixture([ManagedContainer].self, named: "list-all-ports")
            .map { $0.toContainerSummary() }

        let c = try #require(containers.first)
        #expect(c.id == "ports-test")
        #expect(c.state == .running)

        // hostAddress is "0.0.0.0" → omitted
        #expect(c.ports == "8080->80/tcp")
    }

    // MARK: stats.json

    @Test("Maps stats.json: memory/network/blockIO texts, cpuPercent nil")
    func mapStats() throws {
        let stats = try decodeFixture([ContainerResource.ContainerStats].self, named: "stats")
            .map { $0.toContainerStats() }

        #expect(stats.count == 1)

        let s = try #require(stats.first)
        #expect(s.id == "plan-test")

        // cpuUsageUsec is cumulative — the percentage needs two samples (view model)
        #expect(s.cpuPercent == nil)
        #expect(s.cpuUsageUsec == 1631)

        let memText = try #require(s.memoryText)
        #expect(memText.contains("/"))
        #expect(s.memoryLimitBytes == 1_073_741_824)
        #expect(s.networkText != nil)
        #expect(s.blockIOText != nil)
    }

    // MARK: inspect rendering

    @Test("Inspect JSON round-trips the container and keeps slashes unescaped")
    func renderInspect() throws {
        let containers = try decodeFixture([ManagedContainer].self, named: "inspect")
        let json = try renderInspectJSON(containers)

        #expect(json.contains("\"id\" : \"plan-test\""))
        #expect(json.contains("docker.io/library/alpine:latest"))
    }
}

// MARK: - Error classification

@Suite("Container API error classification")
struct ContainerAPIErrorTests {

    @Test("XPC connection errors classify as connectionFailed")
    func connectionError() {
        let error = ContainerizationError(.interrupted, message: "XPC connection error: Connection invalid")
        #expect(ContainerAPIRuntime.classify(error) == .connectionFailed)
    }

    @Test("A connection error wrapped as a cause still classifies as connectionFailed")
    func wrappedConnectionError() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to list containers",
            cause: ContainerizationError(.interrupted, message: "XPC connection error: Connection invalid")
        )
        #expect(ContainerAPIRuntime.classify(error) == .connectionFailed)
    }

    @Test("A server-side notFound wrapped by the client classifies as notFound")
    func wrappedNotFound() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to stop container",
            cause: ContainerizationError(.notFound, message: "container ghost not found")
        )
        #expect(
            ContainerAPIRuntime.classify(error)
                == .notFound(message: "failed to stop container: container ghost not found")
        )
    }

    @Test("Other errors classify as failed with the cause chain's messages")
    func genericFailure() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to delete container",
            cause: ContainerizationError(.invalidState, message: "container is running")
        )
        #expect(
            ContainerAPIRuntime.classify(error)
                == .failed(message: "failed to delete container: container is running")
        )
    }
}

// MARK: - Log tailing

@Suite("Container API log tail")
struct ContainerAPILogTailTests {

    private func handle(for text: String) throws -> FileHandle {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tail-\(UUID().uuidString).log")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try FileHandle(forReadingFrom: url)
    }

    @Test("Returns the last N non-empty lines")
    func lastLines() throws {
        let fh = try handle(for: "one\ntwo\n\nthree\nfour\n")
        defer { try? fh.close() }
        #expect(try ContainerAPIRuntime.tail(fh, lines: 2) == ["three", "four"])
    }

    @Test("Reads across 1 KB chunk boundaries")
    func acrossChunks() throws {
        let lines = (1...500).map { "line \($0)" }
        let fh = try handle(for: lines.joined(separator: "\n"))
        defer { try? fh.close() }
        #expect(try ContainerAPIRuntime.tail(fh, lines: 300) == Array(lines.suffix(300)))
    }

    @Test("An empty log yields no lines")
    func emptyLog() throws {
        let fh = try handle(for: "")
        defer { try? fh.close() }
        #expect(try ContainerAPIRuntime.tail(fh, lines: 50).isEmpty)
    }
}
