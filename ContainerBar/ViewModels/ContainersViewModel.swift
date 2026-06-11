import Observation
import Foundation

// MARK: - Sidebar and detail tab enums

enum SidebarSection: String, CaseIterable, Hashable {
    case all
    case running
    case stopped
    case images
    case settings

    var displayName: String {
        switch self {
        case .all:      return "All"
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .images:   return "Images"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .running:  return "play.circle"
        case .stopped:  return "stop.circle"
        case .images:   return "externaldrive"
        case .settings: return "gear"
        }
    }
}

enum ContainerDetailTab: String, CaseIterable, Hashable {
    case overview
    case logs
    case inspect
    case stats

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .logs:     return "Logs"
        case .inspect:  return "Inspect"
        case .stats:    return "Stats"
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class ContainersViewModel {
    var containers: [ContainerSummary] = []
    var stats: [ContainerStats] = []
    var selectedContainerID: String?
    var sidebarSelection: SidebarSection? = .all
    var detailTab: ContainerDetailTab = .overview
    var logsText: String = ""
    var inspectText: String = ""
    var systemStatus: ContainerSystemStatus = .unknown("Not checked")
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: Image state

    /// All locally-available images, refreshed alongside containers.
    var images: [ImageSummary] = []
    /// The id of the currently-selected image row, driving the detail panel.
    var selectedImageID: String? {
        didSet {
            // Clear stale inspect JSON whenever the selection changes so the
            // detail panel never shows JSON from the previously-selected image.
            if selectedImageID != oldValue {
                imageInspectText = ""
            }
        }
    }
    /// Raw JSON returned by `container image inspect` for the selected image.
    var imageInspectText: String = ""
    /// Transient summary line from the most recent `container image prune` run,
    /// e.g. `"Reclaimed Zero KB in disk space"`.  Cleared when the user dismisses.
    var pruneSummary: String?

    let runtime: any ContainerRuntime

    /// Previous CPU sample per container id: (cumulative usec, wall-clock instant).
    private var cpuSamples: [String: (usec: Int64, time: Date)] = [:]

    init(runtime: some ContainerRuntime) {
        self.runtime = runtime
    }

    // MARK: Computed properties

    var runningContainers: [ContainerSummary] {
        containers.filter { $0.state == .running }
    }

    var selectedContainer: ContainerSummary? {
        guard let selectedContainerID else { return nil }
        return containers.first { $0.id == selectedContainerID }
    }

    var selectedImage: ImageSummary? {
        guard let selectedImageID else { return nil }
        return images.first { $0.id == selectedImageID }
    }

    var filteredContainers: [ContainerSummary] {
        switch sidebarSelection {
        case .all, .none:
            return containers
        case .running:
            return containers.filter { $0.state == .running }
        case .stopped:
            return containers.filter { $0.state != .running }
        case .images, .settings:
            return []
        }
    }

    // MARK: Methods

    /// Refreshes containers, system status, stats, and images.
    /// - Parameter quiet: when `true`, skips the `isLoading` toggle (suitable for
    ///   background polling so the UI doesn't flicker on every cycle).
    func refresh(quiet: Bool = false) async {
        if !quiet { isLoading = true }
        defer { if !quiet { isLoading = false } }

        do {
            // Fetch containers and system status together; a failure here is fatal
            // for the current cycle and routes through the central error handler.
            async let fetchedContainers = runtime.listContainers()
            async let fetchedStatus = runtime.systemStatus()
            containers = try await fetchedContainers
            systemStatus = try await fetchedStatus
            errorMessage = nil
        } catch {
            handle(error)
            return
        }

        // Fetch stats and images concurrently; failures in either are non-fatal so a
        // broken images endpoint never blanks the container list (and vice versa).
        // Each branch is wrapped in a non-throwing async closure so that a throw from
        // one does not cancel the other's in-flight work.
        async let statsResult = fetchStats()
        async let imagesResult = fetchImages()

        switch await statsResult {
        case .success(let freshStats):
            mergeStats(freshStats)
        case .failure(let error):
            // Non-fatal: keep stale stats, surface a non-blocking error message.
            errorMessage = error.localizedDescription
        }

        switch await imagesResult {
        case .success(let freshImages):
            images = Self.markInUse(freshImages, containers: containers)
        case .failure(let error):
            // Non-fatal: keep stale image list, surface a non-blocking error message.
            errorMessage = error.localizedDescription
        }
    }

    /// Non-throwing wrapper for `runtime.stats` used by `refresh` to allow concurrent
    /// `async let` binding without propagating an error that would cancel sibling tasks.
    private func fetchStats() async -> Result<[ContainerStats], any Error> {
        do { return .success(try await runtime.stats(id: nil)) }
        catch { return .failure(error) }
    }

    /// Non-throwing wrapper for `runtime.listImages` used by `refresh` to allow
    /// concurrent `async let` binding without propagating an error that would cancel
    /// sibling tasks.
    private func fetchImages() async -> Result<[ImageSummary], any Error> {
        do { return .success(try await runtime.listImages()) }
        catch { return .failure(error) }
    }

    func refreshStats() async {
        do {
            let freshStats = try await runtime.stats(id: nil)
            mergeStats(freshStats)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Stats merge

    /// Merges freshly-fetched stats into `self.stats` and `self.containers`, computing
    /// CPU % from the delta against the previous sample stored in `cpuSamples`.
    ///
    /// Extracted as a named method so it is exercised by the same path whether the
    /// caller is a quiet or non-quiet refresh.
    private func mergeStats(_ freshStats: [ContainerStats]) {
        let now = Date()
        let currentIDs = Set(freshStats.map(\.id))

        // Prune vanished container ids from the previous-sample store.
        cpuSamples = cpuSamples.filter { currentIDs.contains($0.key) }

        // Build the merged stats array.
        stats = freshStats.map { raw in
            Self.mergedEntry(
                raw: raw,
                previousSamples: cpuSamples,
                now: now
            )
        }

        // Record new samples for the next cycle.
        for raw in freshStats {
            if let usec = raw.cpuUsageUsec {
                cpuSamples[raw.id] = (usec: usec, time: now)
            }
        }

        // Propagate cpuText / memoryText back into containers so table columns update.
        let statsMap = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })
        containers = containers.map { c in
            guard let entry = statsMap[c.id] else { return c }
            var m = c
            // CPU text: formatted percentage, or "–" for the first sample.
            if let pct = entry.cpuPercent {
                m.cpuText = String(format: "%.1f%%", pct)
            } else {
                m.cpuText = "–"
            }
            // Memory text: usage portion only (e.g. "24.3 MB"), from the stats entry.
            if let usageBytes = entry.memoryUsageBytes {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
                formatter.countStyle = .binary
                m.memoryText = formatter.string(fromByteCount: Int64(usageBytes))
            }
            return m
        }
    }

    /// Pure, testable helper: builds one merged `ContainerStats` entry.
    ///
    /// - Parameters:
    ///   - raw: The freshly-decoded stats entry.
    ///   - previousSamples: The caller's previous-sample dictionary (read-only).
    ///   - now: The wall-clock instant of this sample (injected for testability).
    /// - Returns: A stats entry with `cpuPercent` and `cpuText` computed from the delta,
    ///   or `cpuPercent == nil` and `cpuText == "–"` for the first sample.
    nonisolated static func mergedEntry(
        raw: ContainerStats,
        previousSamples: [String: (usec: Int64, time: Date)],
        now: Date
    ) -> ContainerStats {
        var entry = raw

        // CPU %: requires a previous sample for the same container.
        if let currentUsec = raw.cpuUsageUsec,
           let previous = previousSamples[raw.id] {
            let elapsed = now.timeIntervalSince(previous.time)
            entry.cpuPercent = Self.cpuPercent(
                currentUsec: currentUsec,
                previousUsec: previous.usec,
                elapsedSeconds: elapsed
            )
        } else {
            entry.cpuPercent = nil
        }

        return entry
    }

    /// Computes CPU usage percentage from a cumulative-microsecond delta.
    ///
    /// Formula: `(deltaUsec / 1_000_000) / elapsedSeconds × 100`
    /// Result can exceed 100 % on multi-CPU hosts — that is intentional.
    ///
    /// - Parameters:
    ///   - currentUsec: Cumulative CPU microseconds at the current sample.
    ///   - previousUsec: Cumulative CPU microseconds at the previous sample.
    ///   - elapsedSeconds: Wall-clock seconds between the two samples.
    /// - Returns: CPU usage percentage, or `nil` if elapsed time is zero or negative.
    nonisolated static func cpuPercent(
        currentUsec: Int64,
        previousUsec: Int64,
        elapsedSeconds: TimeInterval
    ) -> Double? {
        guard elapsedSeconds > 0 else { return nil }
        let deltaUsec = currentUsec - previousUsec
        return (Double(deltaUsec) / 1_000_000.0) / elapsedSeconds * 100.0
    }

    // MARK: In-use computation

    /// Marks each image as in-use when at least one container references it.
    ///
    /// The match is an exact string comparison between `ImageSummary.reference`
    /// and `ContainerSummary.imageReference`.  A container whose `imageReference`
    /// is `nil` never matches any image.
    ///
    /// This is a pure, `nonisolated` helper so it can be exercised in tests
    /// without a view-model instance (same pattern as `cpuPercent`/`mergedEntry`).
    ///
    /// - Parameters:
    ///   - images: The freshly-decoded image list.
    ///   - containers: The current container list (may include stopped containers).
    /// - Returns: A copy of `images` with `isInUse` set correctly for each element.
    nonisolated static func markInUse(
        _ images: [ImageSummary],
        containers: [ContainerSummary]
    ) -> [ImageSummary] {
        // Build a set of all non-nil image references for O(1) lookup.
        let usedRefs = Set(containers.compactMap(\.imageReference))
        return images.map { image in
            var m = image
            m.isInUse = usedRefs.contains(image.reference)
            return m
        }
    }

    // MARK: Central error handler

    /// Routes runtime errors to the appropriate system-status / error-message state.
    /// Call from any action method's catch block for consistent behaviour.
    private func handle(_ error: Error) {
        if let runtimeError = error as? ContainerRuntimeError {
            switch runtimeError {
            case .cliNotFound:
                systemStatus = .unavailable
                errorMessage = nil
                containers = []
                stats = []
                return
            case .systemNotRunning:
                systemStatus = .stopped
                errorMessage = nil
                containers = []
                stats = []
                return
            default:
                break
            }
        }
        errorMessage = error.localizedDescription
    }

    func loadLogs(_ container: ContainerSummary) async {
        do {
            logsText = try await runtime.logs(id: container.id, lines: 100)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inspect(_ container: ContainerSummary) async {
        do {
            inspectText = try await runtime.inspect(id: container.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ container: ContainerSummary) async {
        do {
            try await runtime.stop(id: container.id)
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    func kill(_ container: ContainerSummary) async {
        do {
            try await runtime.kill(id: container.id)
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    func delete(_ container: ContainerSummary) async {
        do {
            try await runtime.delete(id: container.id)
            if selectedContainerID == container.id {
                selectedContainerID = nil
            }
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    func startSystem() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await runtime.startSystem()
            errorMessage = nil
        } catch {
            handle(error)
            return
        }
        // Use quiet refresh so startSystem retains sole ownership of isLoading
        // for the entire operation, avoiding a false→true→false flicker at the
        // refresh boundary.
        await refresh(quiet: true)
    }

    func stopSystem() async {
        do {
            try await runtime.stopSystem()
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    func select(_ container: ContainerSummary) {
        selectedContainerID = container.id
    }

    func openShell(_ container: ContainerSummary) {
        guard let command = TerminalLauncher.shellCommand(forContainerID: container.id) else {
            errorMessage = "Cannot open a shell for container \"\(container.id)\": invalid identifier."
            return
        }
        TerminalLauncher.open(command: command)
    }

    func prune() async {
        do {
            try await runtime.pruneContainers()
            errorMessage = nil
            await refresh()
            if selectedContainer == nil {
                selectedContainerID = nil
            }
        } catch {
            handle(error)
        }
    }

    // MARK: Image actions

    /// Loads the raw inspect JSON for `image` into `imageInspectText`.
    ///
    /// Read-only: errors set `errorMessage` directly (same pattern as `inspect(_:)`),
    /// not via `handle(_:)`, because a failed inspect should not alter system status.
    func inspectImage(_ image: ImageSummary) async {
        do {
            imageInspectText = try await runtime.inspectImage(reference: image.reference)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes `image` from the local store.
    ///
    /// Clears the selection when it was pointing to the deleted image, then
    /// triggers a full refresh so the list and in-use flags are up to date.
    func deleteImage(_ image: ImageSummary) async {
        do {
            try await runtime.deleteImage(reference: image.reference)
            if selectedImageID == image.id {
                selectedImageID = nil
            }
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    /// Runs `container image prune` (dangling images only) and stores the
    /// CLI summary line in `pruneSummary` for display, then refreshes.
    func pruneImages() async {
        do {
            pruneSummary = try await runtime.pruneImages()
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
        }
    }
}
