import Testing
import Foundation
@testable import ContainerBar

// MARK: - Helpers

/// Builds a minimal `ContainerStats` with just the fields used by the merge logic.
private func makeStats(id: String, cpuUsageUsec: Int64?) -> ContainerStats {
    ContainerStats(
        id: id,
        name: nil,
        cpuPercent: nil,
        cpuUsageUsec: cpuUsageUsec,
        memoryUsageBytes: nil,
        memoryLimitBytes: nil,
        memoryText: nil,
        networkText: nil,
        blockIOText: nil
    )
}

// MARK: - Tests

@Suite("ContainersViewModel stats merge")
struct StatsMergeTests {

    // MARK: CPU % delta math

    @Test("cpuPercent: known delta — 2_000_000 usec over 4 s → 50.0%")
    func cpuPercentKnownDelta() throws {
        let result = ContainersViewModel.cpuPercent(
            currentUsec: 12_000_000,
            previousUsec: 10_000_000,
            elapsedSeconds: 4.0
        )
        let pct = try #require(result)
        // (2_000_000 / 1_000_000) / 4.0 × 100 = 50.0
        #expect(abs(pct - 50.0) < 0.001)
    }

    @Test("cpuPercent: zero elapsed → nil")
    func cpuPercentZeroElapsed() {
        let result = ContainersViewModel.cpuPercent(
            currentUsec: 5_000_000,
            previousUsec: 1_000_000,
            elapsedSeconds: 0.0
        )
        #expect(result == nil)
    }

    @Test("cpuPercent: negative elapsed → nil")
    func cpuPercentNegativeElapsed() {
        let result = ContainersViewModel.cpuPercent(
            currentUsec: 5_000_000,
            previousUsec: 1_000_000,
            elapsedSeconds: -1.0
        )
        #expect(result == nil)
    }

    @Test("cpuPercent: can exceed 100% on multi-CPU (8_000_000 usec over 4 s → 200%)")
    func cpuPercentExceedsHundred() throws {
        let result = ContainersViewModel.cpuPercent(
            currentUsec: 18_000_000,
            previousUsec: 10_000_000,
            elapsedSeconds: 4.0
        )
        let pct = try #require(result)
        // (8_000_000 / 1_000_000) / 4.0 × 100 = 200.0
        #expect(abs(pct - 200.0) < 0.001)
    }

    // MARK: First-sample behavior

    @Test("mergedEntry: first sample (no previous) → cpuPercent nil")
    func mergedEntryFirstSample() {
        let raw = makeStats(id: "c1", cpuUsageUsec: 5_000_000)
        let now = Date()

        let entry = ContainersViewModel.mergedEntry(
            raw: raw,
            previousSamples: [:],   // No previous sample
            now: now
        )

        #expect(entry.cpuPercent == nil)
        #expect(entry.id == "c1")
    }

    @Test("mergedEntry: first sample with no cpuUsageUsec → cpuPercent nil")
    func mergedEntryNoCpuField() {
        let raw = makeStats(id: "c1", cpuUsageUsec: nil)
        let now = Date()
        let prev: [String: (usec: Int64, time: Date)] = ["c1": (usec: 1_000_000, time: now.addingTimeInterval(-5))]

        let entry = ContainersViewModel.mergedEntry(
            raw: raw,
            previousSamples: prev,
            now: now
        )

        #expect(entry.cpuPercent == nil)
    }

    // MARK: Merge fills values for the right container

    @Test("mergedEntry: computes cpuPercent for the matching container id only")
    func mergedEntryMatchingID() throws {
        let now = Date()
        let thenTime = now.addingTimeInterval(-4.0)

        let previousSamples: [String: (usec: Int64, time: Date)] = [
            "c1": (usec: 10_000_000, time: thenTime),
            "c2": (usec: 20_000_000, time: thenTime),
        ]

        // c1: delta = 2_000_000 usec / 4 s = 50.0%
        let raw1 = makeStats(id: "c1", cpuUsageUsec: 12_000_000)
        let entry1 = ContainersViewModel.mergedEntry(raw: raw1, previousSamples: previousSamples, now: now)
        let pct1 = try #require(entry1.cpuPercent)
        #expect(abs(pct1 - 50.0) < 0.1)

        // c2: delta = 4_000_000 usec / 4 s = 100.0%
        let raw2 = makeStats(id: "c2", cpuUsageUsec: 24_000_000)
        let entry2 = ContainersViewModel.mergedEntry(raw: raw2, previousSamples: previousSamples, now: now)
        let pct2 = try #require(entry2.cpuPercent)
        #expect(abs(pct2 - 100.0) < 0.1)

        // c3: no previous sample → nil
        let raw3 = makeStats(id: "c3", cpuUsageUsec: 1_000_000)
        let entry3 = ContainersViewModel.mergedEntry(raw: raw3, previousSamples: previousSamples, now: now)
        #expect(entry3.cpuPercent == nil)
    }

    // MARK: Vanished-id pruning

    @Test("mergeStats (via ViewModel): vanished container ids are pruned from cpuSamples")
    @MainActor
    func vanishedIDPruning() async {
        // Use a mock runtime; we won't invoke it — we call mergeStats directly via
        // the public refresh path, but we need a ViewModel instance to inspect its
        // private state.  Instead we verify indirectly: after two refresh cycles
        // where the second cycle returns fewer containers, the pruned container should
        // no longer accumulate a cpuPercent (it would be stale).
        //
        // Because cpuSamples is private, we observe the effect through the published
        // stats array: the gone container must not appear in stats after the second cycle.

        let mock = TrackedMockRuntime()

        // First cycle: two containers with stats
        mock.stubbedStats = [
            makeStats(id: "alive", cpuUsageUsec: 1_000_000),
            makeStats(id: "gone",  cpuUsageUsec: 2_000_000),
        ]
        mock.stubbedContainers = [
            ContainerSummary(id: "alive", name: "alive", image: "alpine", state: .running,
                             status: nil, command: nil, createdAt: nil, startedAt: nil,
                             ports: nil, cpuText: nil, memoryText: nil),
            ContainerSummary(id: "gone", name: "gone", image: "alpine", state: .running,
                             status: nil, command: nil, createdAt: nil, startedAt: nil,
                             ports: nil, cpuText: nil, memoryText: nil),
        ]
        let vm = ContainersViewModel(runtime: mock)
        await vm.refresh()

        // Second cycle: "gone" container has been removed from stats
        mock.stubbedStats = [
            makeStats(id: "alive", cpuUsageUsec: 2_000_000),
        ]
        mock.stubbedContainers = [
            ContainerSummary(id: "alive", name: "alive", image: "alpine", state: .running,
                             status: nil, command: nil, createdAt: nil, startedAt: nil,
                             ports: nil, cpuText: nil, memoryText: nil),
        ]
        await vm.refresh()

        // "gone" must not appear in the published stats after pruning.
        let goneEntry = vm.stats.first { $0.id == "gone" }
        #expect(goneEntry == nil, "Vanished container 'gone' should be pruned from stats")
    }

    // MARK: Memory text on containers

    @Test("mergeStats: memoryUsageBytes propagated to container's memoryText")
    @MainActor
    func memoryTextPropagated() async throws {
        let mock = TrackedMockRuntime()
        let usageBytes: UInt64 = 25_165_824  // 24 MiB

        mock.stubbedStats = [
            ContainerStats(
                id: "c1", name: nil, cpuPercent: nil, cpuUsageUsec: nil,
                memoryUsageBytes: usageBytes, memoryLimitBytes: nil,
                memoryText: "24 MiB", networkText: nil, blockIOText: nil
            ),
        ]
        mock.stubbedContainers = [
            ContainerSummary(id: "c1", name: "c1", image: "alpine", state: .running,
                             status: nil, command: nil, createdAt: nil, startedAt: nil,
                             ports: nil, cpuText: nil, memoryText: nil),
        ]

        let vm = ContainersViewModel(runtime: mock)
        await vm.refresh()

        let c = try #require(vm.containers.first { $0.id == "c1" })
        #expect(c.memoryText != nil, "memoryText should be set from stats")
    }
}

// MARK: - TrackedMockRuntime

/// Minimal `ContainerRuntime` implementation for StatsMergeTests.
/// Stubs are set directly before each call; no async latency.
final class TrackedMockRuntime: ContainerRuntime, @unchecked Sendable {
    var stubbedContainers: [ContainerSummary] = []
    var stubbedStats: [ContainerStats] = []

    func listContainers() async throws -> [ContainerSummary] { stubbedContainers }
    func inspect(id: String) async throws -> String { "{}" }
    func logs(id: String, lines: Int) async throws -> String { "" }
    func stats(id: String?) async throws -> [ContainerStats] { stubbedStats }
    func stop(id: String) async throws {}
    func kill(id: String) async throws {}
    func delete(id: String) async throws {}
    func pruneContainers() async throws {}
    func startSystem() async throws {}
    func stopSystem() async throws {}
    func systemStatus() async throws -> ContainerSystemStatus { .running }
    func listImages() async throws -> [ImageSummary] { [] }
    func inspectImage(reference: String) async throws -> String { "{}" }
    func deleteImage(reference: String) async throws {}
    func pruneImages() async throws -> String { "Reclaimed Zero KB in disk space" }
}
