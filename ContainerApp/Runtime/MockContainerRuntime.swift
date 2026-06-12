import Foundation

// MARK: - Canned state (actor-isolated for Swift 6 Sendable correctness)

actor MockStore {
    var containers: [ContainerSummary] = MockContainerRuntime.seedContainers
    var images: [ImageSummary] = MockContainerRuntime.seedImages

    func list() -> [ContainerSummary] { containers }
    func listImages() -> [ImageSummary] { images }

    /// Inserts `container` into the store, or replaces an existing entry with the same id.
    func add(_ container: ContainerSummary) {
        if let idx = containers.firstIndex(where: { $0.id == container.id }) {
            containers[idx] = container
        } else {
            containers.append(container)
        }
    }

    func start(id: String) {
        containers = containers.map { c in
            guard c.id == id else { return c }
            var m = c
            m.state = .running
            m.status = "Up Less than a second"
            m.startedAt = Date()
            return m
        }
    }

    func stop(id: String) {
        containers = containers.map { c in
            guard c.id == id else { return c }
            var m = c
            m.state = .stopped
            m.status = "Exited (0)"
            m.cpuText = nil
            m.memoryText = nil
            return m
        }
    }

    func kill(id: String) {
        containers = containers.map { c in
            guard c.id == id else { return c }
            var m = c
            m.state = .exited
            m.status = "Exited (137)"
            m.cpuText = nil
            m.memoryText = nil
            return m
        }
    }

    func delete(id: String) {
        containers.removeAll { $0.id == id }
    }

    func prune() {
        containers.removeAll { $0.state != .running }
    }

    func deleteImage(reference: String) {
        images.removeAll { $0.reference == reference }
    }

    /// Removes only images not referenced by any container and returns a plausible
    /// "Reclaimed … in disk space" summary string.
    func pruneImages(containerRefs: Set<String>) -> String {
        var reclaimedBytes: Int64 = 0
        images.removeAll { image in
            guard !containerRefs.contains(image.reference) else { return false }
            reclaimedBytes += image.sizeBytes ?? 0
            return true
        }
        if reclaimedBytes == 0 {
            return "Reclaimed Zero KB in disk space"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        let formatted = formatter.string(fromByteCount: reclaimedBytes)
        return "Reclaimed \(formatted) in disk space"
    }
}

// MARK: - Mock runtime

/// Phase-1 mock that returns canned containers and simulates ~200 ms network latency.
/// Mutating actions (stop / kill / delete) update the in-memory store so the UI reacts.
final class MockContainerRuntime: ContainerRuntime {
    /// Exposed so `MockComposeRuntime` can add/start containers named `<project>-<service>`.
    let store = MockStore()

    // Seed data is static so it can be referenced before `self` is available.
    fileprivate static let seedContainers: [ContainerSummary] = {
        let now = Date()
        let cal = Calendar.current
        return [
            ContainerSummary(
                id: "a1b2c3d4e5f6",
                name: "web",
                image: "nginx:latest",
                state: .running,
                status: "Up 3 hours",
                command: "nginx -g 'daemon off;'",
                createdAt: cal.date(byAdding: .hour, value: -4, to: now),
                startedAt: cal.date(byAdding: .hour, value: -3, to: now),
                ports: "0.0.0.0:8080->80/tcp",
                cpuText: "0.4%",
                memoryText: "24.3 MB",
                imageReference: "docker.io/library/nginx:latest"
            ),
            ContainerSummary(
                id: "b2c3d4e5f6a1",
                name: "postgres",
                image: "postgres:17",
                state: .running,
                status: "Up 3 hours",
                command: "postgres",
                createdAt: cal.date(byAdding: .hour, value: -4, to: now),
                startedAt: cal.date(byAdding: .hour, value: -3, to: now),
                ports: "0.0.0.0:5432->5432/tcp",
                cpuText: "1.2%",
                memoryText: "512.0 MB",
                imageReference: "docker.io/library/postgres:17"
            ),
            ContainerSummary(
                id: "c3d4e5f6a1b2",
                name: "redis",
                image: "redis:7",
                state: .running,
                status: "Up 2 hours",
                command: "redis-server",
                createdAt: cal.date(byAdding: .hour, value: -3, to: now),
                startedAt: cal.date(byAdding: .hour, value: -2, to: now),
                ports: "0.0.0.0:6379->6379/tcp",
                cpuText: "0.1%",
                memoryText: "8.7 MB",
                imageReference: "docker.io/library/redis:7"
            ),
            ContainerSummary(
                id: "d4e5f6a1b2c3",
                name: "worker",
                image: "alpine:3",
                state: .stopped,
                status: "Exited (0) 30 minutes ago",
                command: "/bin/sh -c 'run-worker.sh'",
                createdAt: cal.date(byAdding: .hour, value: -2, to: now),
                startedAt: cal.date(byAdding: .minute, value: -90, to: now),
                ports: nil,
                cpuText: nil,
                memoryText: nil,
                imageReference: "docker.io/library/alpine:3"
            ),
            ContainerSummary(
                id: "e5f6a1b2c3d4",
                name: "old-migrate",
                image: "busybox:latest",
                state: .exited,
                status: "Exited (1) 2 days ago",
                command: "/bin/sh -c 'migrate.sh'",
                createdAt: cal.date(byAdding: .day, value: -3, to: now),
                startedAt: cal.date(byAdding: .day, value: -2, to: now),
                ports: nil,
                cpuText: nil,
                memoryText: nil,
                imageReference: "docker.io/library/busybox:latest"
            ),
        ]
    }()

    /// Seed images — one per distinct container image reference, plus one unused image
    /// so the future In-Use column shows both states.
    ///
    /// `isInUse` is `false` in the seeds; the view model computes it later by
    /// cross-referencing against the container list.
    fileprivate static let seedImages: [ImageSummary] = {
        let now = Date()
        let cal = Calendar.current
        return [
            ImageSummary(
                id: "a3ed12f5bc10d8f4e6a2c9b7e5d3f1a0b2c4e6d8f0a2b4c6e8d0f2a4b6c8e0",
                reference: "docker.io/library/nginx:latest",
                displayName: "nginx",
                tag: "latest",
                digestShort: "a3ed12f5bc10",
                createdAt: cal.date(byAdding: .day, value: -5, to: now),
                sizeBytes: 71_800_000,
                architectures: ["arm64"]
            ),
            ImageSummary(
                id: "b4fe23a6cd21e9f5f7b3d0c8f6e4a2b1c3d5e7f9b1c3e5a7c9e1b3d5f7a9c1",
                reference: "docker.io/library/postgres:17",
                displayName: "postgres",
                tag: "17",
                digestShort: "b4fe23a6cd21",
                createdAt: cal.date(byAdding: .day, value: -10, to: now),
                sizeBytes: 432_000_000,
                architectures: ["arm64"]
            ),
            ImageSummary(
                id: "c5af34b7de32f0a6a8c4e1d9a7f5b3c2d4f6a8b0c2d4f6a8b0c2d4f6a8b0c2",
                reference: "docker.io/library/redis:7",
                displayName: "redis",
                tag: "7",
                digestShort: "c5af34b7de32",
                createdAt: cal.date(byAdding: .day, value: -7, to: now),
                sizeBytes: 117_000_000,
                architectures: ["arm64"]
            ),
            ImageSummary(
                id: "d6b045c8ef43a1b7b9d5f2e0b8a6c4d3e5a7c9e1b3d5f7a9c1e3a5b7d9f1a3",
                reference: "docker.io/library/alpine:3",
                displayName: "alpine",
                tag: "3",
                digestShort: "d6b045c8ef43",
                createdAt: cal.date(byAdding: .day, value: -14, to: now),
                sizeBytes: 3_800_000,
                architectures: ["arm64"]
            ),
            ImageSummary(
                id: "e7c156d9f054b2c8c0e6a3f1c9b7d5e4f6b8d0f2c4e6b8d0f2c4e6b8d0f2c4",
                reference: "docker.io/library/busybox:latest",
                displayName: "busybox",
                tag: "latest",
                digestShort: "e7c156d9f054",
                createdAt: cal.date(byAdding: .day, value: -30, to: now),
                sizeBytes: 2_100_000,
                architectures: ["arm64"]
            ),
            // One unused image — no container references this ref;
            // allows the future In-Use column to show both states.
            ImageSummary(
                id: "f8d267e0a165c3d9d1f7b4a2d0c8e6f5a7b9e1c3a5d7b9e1c3a5d7b9e1c3a5",
                reference: "docker.io/library/ubuntu:24.04",
                displayName: "ubuntu",
                tag: "24.04",
                digestShort: "f8d267e0a165",
                createdAt: cal.date(byAdding: .day, value: -60, to: now),
                sizeBytes: 29_900_000,
                architectures: ["arm64"]
            ),
        ]
    }()

    private static let fakeLogs: [String: String] = [
        "a1b2c3d4e5f6": """
            2025-06-10T08:00:00Z nginx/1.27.0: Starting nginx worker processes
            2025-06-10T08:00:01Z nginx: worker process started (pid 12)
            2025-06-10T08:01:22Z 192.168.1.5 - - [10/Jun/2025:08:01:22 +0000] "GET / HTTP/1.1" 200 615
            2025-06-10T08:02:05Z 192.168.1.5 - - [10/Jun/2025:08:02:05 +0000] "GET /health HTTP/1.1" 200 3
            2025-06-10T08:03:11Z 192.168.1.6 - - [10/Jun/2025:08:03:11 +0000] "POST /api/data HTTP/1.1" 201 44
            2025-06-10T09:15:00Z 192.168.1.7 - - [10/Jun/2025:09:15:00 +0000] "GET /metrics HTTP/1.1" 200 1024
            """,
        "b2c3d4e5f6a1": """
            2025-06-10T08:00:00Z PostgreSQL 17.0 on aarch64-unknown-linux-gnu
            2025-06-10T08:00:00Z LOG:  starting PostgreSQL 17.0 on aarch64-unknown-linux-gnu
            2025-06-10T08:00:01Z LOG:  listening on IPv4 address "0.0.0.0", port 5432
            2025-06-10T08:00:01Z LOG:  database system is ready to accept connections
            2025-06-10T08:05:33Z LOG:  checkpoint starting: time
            2025-06-10T08:05:34Z LOG:  checkpoint complete: wrote 3 buffers (0.0%)
            """,
        "c3d4e5f6a1b2": """
            2025-06-10T09:00:00Z 1:M 10 Jun 2025 09:00:00.000 # oO0OoO0Oo Redis is starting
            2025-06-10T09:00:00Z 1:M 10 Jun 2025 09:00:00.001 * Redis version=7.2.0, bits=64
            2025-06-10T09:00:00Z 1:M 10 Jun 2025 09:00:00.002 * Running mode=standalone, port=6379
            2025-06-10T09:00:00Z 1:M 10 Jun 2025 09:00:00.003 # Server initialized
            2025-06-10T09:00:00Z 1:M 10 Jun 2025 09:00:00.004 * Ready to accept connections
            """,
        "d4e5f6a1b2c3": """
            2025-06-10T10:00:00Z worker: starting up
            2025-06-10T10:00:01Z worker: connected to redis at redis:6379
            2025-06-10T10:00:01Z worker: waiting for jobs...
            2025-06-10T10:28:54Z worker: processed job id=9f3a cleanly, exit 0
            """,
        "e5f6a1b2c3d4": """
            2025-06-08T06:00:00Z migrate: starting schema migration v42
            2025-06-08T06:00:01Z migrate: connecting to postgres://postgres:5432/app
            2025-06-08T06:00:02Z migrate: ERROR: relation "users_v2" already exists
            2025-06-08T06:00:02Z migrate: exiting with status 1
            """,
    ]

    private static func fakeInspect(for container: ContainerSummary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload: [String: String] = [
            "Id": container.id,
            "Name": container.name,
            "Image": container.image,
            "State": container.state.rawValue,
            "Status": container.status ?? "",
            "Command": container.command ?? "",
        ]
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func fakeImageInspect(for image: ImageSummary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload: [String: String] = [
            "id": image.id,
            "reference": image.reference,
            "displayName": image.displayName,
            "tag": image.tag ?? "",
            "digestShort": image.digestShort,
            "sizeBytes": image.sizeBytes.map { String($0) } ?? "0",
        ]
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let fakeStats: [ContainerStats] = [
        ContainerStats(
            id: "a1b2c3d4e5f6",
            name: "web",
            cpuPercent: 0.4,
            cpuUsageUsec: nil,
            memoryUsageBytes: 24_900_000,
            memoryLimitBytes: 2_147_483_648,
            memoryText: "24.3 MB / 2.0 GB",
            networkText: "1.2 MB / 300 KB",
            blockIOText: "0 B / 0 B"
        ),
        ContainerStats(
            id: "b2c3d4e5f6a1",
            name: "postgres",
            cpuPercent: 1.2,
            cpuUsageUsec: nil,
            memoryUsageBytes: 536_870_912,
            memoryLimitBytes: 4_294_967_296,
            memoryText: "512.0 MB / 4.0 GB",
            networkText: "4.5 MB / 1.1 MB",
            blockIOText: "88 MB / 12 MB"
        ),
        ContainerStats(
            id: "c3d4e5f6a1b2",
            name: "redis",
            cpuPercent: 0.1,
            cpuUsageUsec: nil,
            memoryUsageBytes: 9_100_000,
            memoryLimitBytes: 2_147_483_648,
            memoryText: "8.7 MB / 2.0 GB",
            networkText: "220 KB / 85 KB",
            blockIOText: "0 B / 0 B"
        ),
    ]

    // MARK: ContainerRuntime

    func listContainers() async throws -> [ContainerSummary] {
        try await Task.sleep(for: .milliseconds(200))
        return await store.list()
    }

    func inspect(id: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        let containers = await store.list()
        guard let container = containers.first(where: { $0.id == id }) else {
            throw ContainerRuntimeError.notFound(id: id)
        }
        return Self.fakeInspect(for: container)
    }

    func logs(id: String, lines: Int) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        return Self.fakeLogs[id] ?? "(no logs available for \(id))"
    }

    func stats(id: String?) async throws -> [ContainerStats] {
        try await Task.sleep(for: .milliseconds(200))
        if let id {
            return Self.fakeStats.filter { $0.id == id }
        }
        return Self.fakeStats
    }

    func start(id: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.start(id: id)
    }

    func stop(id: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.stop(id: id)
    }

    func kill(id: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.kill(id: id)
    }

    func delete(id: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.delete(id: id)
    }

    func pruneContainers() async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.prune()
    }

    func startSystem() async throws {
        try await Task.sleep(for: .milliseconds(500))
        // No-op in mock — system is always "running"
    }

    func stopSystem() async throws {
        try await Task.sleep(for: .milliseconds(500))
        // No-op in mock
    }

    func systemStatus() async throws -> ContainerSystemStatus {
        try await Task.sleep(for: .milliseconds(200))
        return .running
    }

    // MARK: - Image management

    func listImages() async throws -> [ImageSummary] {
        try await Task.sleep(for: .milliseconds(200))
        return await store.listImages()
    }

    /// Returns a small pretty-printed JSON blob for the given reference.
    /// Throws `.notFound(id:)` for unknown references, matching the real CLI behaviour.
    func inspectImage(reference: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        let images = await store.listImages()
        guard let image = images.first(where: { $0.reference == reference }) else {
            throw ContainerRuntimeError.notFound(id: reference)
        }
        return Self.fakeImageInspect(for: image)
    }

    /// Removes the image matching `reference` from the in-memory store.
    func deleteImage(reference: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        await store.deleteImage(reference: reference)
    }

    /// Removes only images not referenced by any container and returns a plausible
    /// "Reclaimed … in disk space" summary string.
    func pruneImages() async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        let containers = await store.list()
        let containerRefs = Set(containers.compactMap { $0.imageReference })
        return await store.pruneImages(containerRefs: containerRefs)
    }
}
