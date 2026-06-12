import Observation
import Foundation

// MARK: - Sidebar and detail tab enums

enum SidebarSection: String, CaseIterable, Hashable {
    case all
    case running
    case stopped
    case images
    case compose
    case settings

    var displayName: String {
        switch self {
        case .all:      return "All"
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .images:   return "Images"
        case .compose:  return "Compose"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .running:  return "play.circle"
        case .stopped:  return "stop.circle"
        case .images:   return "externaldrive"
        case .compose:  return "square.stack.3d.up"
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
    var selectedContainerID: String? {
        didSet {
            // Clear stale per-container text whenever the selection changes so the
            // detail panel never shows logs/inspect JSON from the previously-selected
            // container (same pattern as `selectedImageID`).
            if selectedContainerID != oldValue {
                logsText = ""
                inspectText = ""
            }
        }
    }
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

    // MARK: Compose state

    /// All registered compose projects, reparsed from disk on each refresh.
    var composeProjects: [ComposeProject] = []

    /// The id (absolute compose-file path) of the currently-selected project row.
    var selectedComposeProjectID: String? {
        didSet {
            // Clear stale action output whenever the selection changes so the
            // detail panel never shows output from a previously-selected project.
            if selectedComposeProjectID != oldValue {
                lastComposeOutput = nil
            }
        }
    }

    /// `nil` = not yet probed; `true` = binary found; `false` = binary absent → install prompt.
    var composeAvailable: Bool?

    /// Version string returned by `container-compose --version`, e.g.
    /// `"container-compose version 0.12.0"`. Set alongside `composeAvailable`.
    var composeVersion: String?

    /// Project ids with an in-flight up/down/build action.
    var busyComposeProjects: Set<String> = []

    /// Trimmed stdout of the last finished compose action, displayed in the detail panel.
    var lastComposeOutput: String?

    let runtime: any ContainerRuntime
    private let composeRuntime: any ComposeRuntime
    private let composeStore: ComposeProjectStore

    /// Previous CPU sample per container id: (cumulative usec, wall-clock instant).
    private var cpuSamples: [String: (usec: Int64, time: Date)] = [:]

    init(
        runtime: some ContainerRuntime,
        composeRuntime: some ComposeRuntime = ContainerComposeCLIRuntime(),
        composeStore: ComposeProjectStore = ComposeProjectStore()
    ) {
        self.runtime = runtime
        self.composeRuntime = composeRuntime
        self.composeStore = composeStore
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

    var selectedComposeProject: ComposeProject? {
        guard let selectedComposeProjectID else { return nil }
        return composeProjects.first { $0.id == selectedComposeProjectID }
    }

    var filteredContainers: [ContainerSummary] {
        switch sidebarSelection {
        case .all, .none:
            return containers
        case .running:
            return containers.filter { $0.state == .running }
        case .stopped:
            return containers.filter { $0.state != .running }
        case .images, .compose, .settings:
            return []
        }
    }

    // MARK: Methods

    /// Refreshes containers, system status, stats, images, and compose projects.
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

        // Fetch stats, images, and compose projects concurrently; failures in any
        // are non-fatal so a broken endpoint never blanks the container list.
        // Each branch is wrapped in a non-throwing async closure so that a throw from
        // one does not cancel the other's in-flight work.
        async let statsResult = fetchStats()
        async let imagesResult = fetchImages()
        async let composeResult = fetchComposeProjects()

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

        switch await composeResult {
        case .success(let (projects, version)):
            composeProjects = projects
            // version is non-nil only on the first probe (composeAvailable == nil).
            if let version {
                composeAvailable = true
                composeVersion = version
            }
        case .failure:
            // Non-fatal: keep stale compose project list.
            break
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

    /// Reloads compose-file paths from the store and reparses each file off the main
    /// actor (disk I/O).  Also probes `composeRuntime.version()` the first time only.
    ///
    /// Returns the reparsed project list and — when a version probe was performed —
    /// the version string.  The version is `nil` when no probe was needed (subsequent
    /// calls after `composeAvailable` is already set).
    ///
    /// Parse failures for individual files produce a stub row with `isMissing = true`
    /// instead of aborting the entire list (same resilience policy as the image list).
    private func fetchComposeProjects() async -> Result<([ComposeProject], String?), any Error> {
        let paths = composeStore.paths()

        // Reparse each file off the main actor to avoid blocking the UI during disk I/O.
        let projects: [ComposeProject] = await Task.detached(priority: .utility) {
            paths.map { path -> ComposeProject in
                let fileURL = URL(fileURLWithPath: path)
                do {
                    return try ComposeFileParser.load(fileURL: fileURL)
                } catch {
                    // Parse failure: return a stub with isMissing so the row is still
                    // visible with a warning indicator.
                    let folderURL = fileURL.deletingLastPathComponent()
                    let projectName = ComposeFileParser.projectName(name: nil, folderURL: folderURL)
                    var stub = ComposeProject(
                        id: path,
                        fileURL: fileURL,
                        projectName: projectName,
                        displayName: folderURL.lastPathComponent,
                        serviceNames: [],
                        serviceImages: [:]
                    )
                    stub.isMissing = true
                    return stub
                }
            }
        }.value

        // Probe the compose binary version only when not yet determined.
        var versionString: String?
        if composeAvailable == nil {
            versionString = await composeRuntime.version()
            if versionString == nil {
                // Binary was not found — mark as unavailable immediately.
                composeAvailable = false
            }
        }

        return .success((projects, versionString))
    }

    func refreshStats() async {
        do {
            let freshStats = try await runtime.stats(id: nil)
            mergeStats(freshStats)
            // Re-run in-use marking so images reflect the latest container list.
            images = Self.markInUse(images, containers: containers)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resets the compose availability probe so the next `refresh()` re-checks the binary.
    ///
    /// Call this from Settings when the user changes the `containerComposeCLIPath` preference,
    /// or from the install-prompt Retry button.
    func reprobeCompose() async {
        composeAvailable = nil
        composeVersion = nil
        await refresh(quiet: true)
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

    // MARK: Compose status derivation

    /// Derives the live status of each service in `project` by matching its explicit
    /// `container_name`, or the default `"<project.projectName>-<serviceName>"`,
    /// against `containers`.
    ///
    /// The match is **exact** — a project named `"web"` does NOT claim a container
    /// named `"web-app-cache"` from a different project.  A service with no matching
    /// container gets `state == nil` ("not created").
    ///
    /// This is a pure, `nonisolated` helper so it can be exercised in tests without
    /// a view-model instance (same pattern as `markInUse`).
    ///
    /// - Parameters:
    ///   - project: The compose project whose service list drives the output.
    ///   - containers: The current container list (may include stopped containers).
    /// - Returns: One `ComposeServiceStatus` per service, in `project.serviceNames` order.
    nonisolated static func serviceStatuses(
        for project: ComposeProject,
        containers: [ContainerSummary]
    ) -> [ComposeServiceStatus] {
        // Build a map for O(1) container lookup by id.
        let containerMap = Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0) })
        return project.serviceNames.map { serviceName in
            let expectedID = serviceContainerID(for: serviceName, in: project)
            let matchingContainer = containerMap[expectedID]
            return ComposeServiceStatus(
                id: expectedID,
                serviceName: serviceName,
                image: project.serviceImages[serviceName],
                state: matchingContainer?.state
            )
        }
    }

    nonisolated static func serviceContainerID(
        for serviceName: String,
        in project: ComposeProject
    ) -> String {
        project.serviceContainerNames[serviceName]
            ?? "\(project.projectName)-\(serviceName)"
    }

    // MARK: Duplicate project name detection

    /// Project names that appear on two or more non-missing compose projects.
    ///
    /// Two registered projects that share the same `projectName` derive identical
    /// container ids (`<project>-<service>`), causing silent container-id collisions.
    /// Missing-file stubs are excluded: they produce no containers so they cannot
    /// collide with anything.
    ///
    /// Computed as a convenience over `detectDuplicateProjectNames` so that SwiftUI
    /// views can read it as a plain property with no extra bookkeeping.
    var duplicateProjectNames: Set<String> {
        Self.detectDuplicateProjectNames(composeProjects)
    }

    /// Pure, testable helper: returns the set of project names that appear on two or
    /// more non-missing projects in `projects`.
    ///
    /// - Parameter projects: The full compose project list to inspect.
    /// - Returns: Project names where the count of non-missing projects sharing that
    ///   name is ≥ 2.  Returns an empty set when there are no duplicates.
    nonisolated static func detectDuplicateProjectNames(_ projects: [ComposeProject]) -> Set<String> {
        var counts: [String: Int] = [:]
        for project in projects where !project.isMissing {
            counts[project.projectName, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
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
                images = []
                // composeProjects comes from disk — do not clear it here.
                return
            case .systemNotRunning:
                systemStatus = .stopped
                errorMessage = nil
                containers = []
                stats = []
                images = []
                // composeProjects comes from disk — do not clear it here.
                return
            case .composeCLINotFound:
                // Mark compose as unavailable without touching container/system state.
                composeAvailable = false
                return
            default:
                break
            }
        }
        errorMessage = error.localizedDescription
    }

    /// Loads the last 100 log lines for `container` into `logsText`.
    /// - Parameter quiet: when `true` (background polling), failures keep the
    ///   current text and never touch `errorMessage`, so a transient CLI hiccup
    ///   doesn't raise the error banner every poll cycle.
    func loadLogs(_ container: ContainerSummary, quiet: Bool = false) async {
        do {
            let text = try await runtime.logs(id: container.id, lines: 100)
            // The owning `.task(id:)` is cancelled when the selection changes;
            // drop a late result so it can't overwrite the new container's logs.
            guard !Task.isCancelled else { return }
            logsText = text
            if !quiet { errorMessage = nil }
        } catch is CancellationError {
            // Selection changed mid-load — nothing to report.
        } catch {
            if !quiet { errorMessage = error.localizedDescription }
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

    func start(_ container: ContainerSummary) async {
        do {
            try await runtime.start(id: container.id)
            errorMessage = nil
            await refresh()
        } catch {
            handle(error)
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

    // MARK: Compose actions

    /// Runs `container-compose up -d` for all services in `project`.
    ///
    /// The underlying work is launched in a fire-and-forget `Task` so image pulls
    /// (which can take minutes) do not block refresh or other UI interaction.
    /// On success, `lastComposeOutput` is set to the trimmed CLI stdout and a quiet
    /// refresh runs.  On failure, the quiet refresh runs first so container state is
    /// up to date before `errorMessage` is set — ensuring the error survives the refresh.
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func upProject(_ project: ComposeProject) -> Task<Void, Never> {
        upProject(project, rebuild: false, noCache: false)
    }

    /// Runs `container-compose up -d` for all services, with optional rebuild/no-cache.
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func upProject(_ project: ComposeProject, rebuild: Bool, noCache: Bool) -> Task<Void, Never> {
        composeAction(project) { progress in
            try await self.composeRuntime.up(
                project: project,
                services: [],
                rebuild: rebuild,
                noCache: noCache,
                progress: progress
            )
        }
    }

    /// Runs `container-compose build` for all services in `project`.
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func buildProject(_ project: ComposeProject) -> Task<Void, Never> {
        composeAction(project) { progress in
            try await self.composeRuntime.build(
                project: project,
                services: [],
                noCache: false,
                progress: progress
            )
        }
    }

    /// Stops all running containers for `project` by calling `ContainerRuntime.stop(id:)`
    /// on each matched container in dependency-aware stop order (dependents before
    /// their dependencies, reverse YAML order for services with no dependencies).
    ///
    /// Does NOT call `ComposeRuntime` — `container-compose down` 0.12.0 has an XPC
    /// protocol mismatch with container runtime 1.0.0.  Native `container stop` is used
    /// instead (verified working on compose-created containers).
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func downProject(_ project: ComposeProject) -> Task<Void, Never> {
        // Derive the running containers for this project in dependency-aware stop order.
        // Snapshot containers on the MainActor before crossing into the Task closure.
        let stopOrderNames = ComposeFileParser.stopOrder(
            serviceNames: project.serviceNames,
            dependencies: project.serviceDependencies
        )
        let statuses = Self.serviceStatuses(for: project, containers: containers)
        let statusMap = Dictionary(uniqueKeysWithValues: statuses.map { ($0.serviceName, $0) })
        let runningIDs = stopOrderNames
            .compactMap { status -> String? in
                guard statusMap[status]?.state == .running else { return nil }
                return statusMap[status]?.id
            }

        return composeAction(project) { _ in
            var stopped = 0
            for id in runningIDs {
                try await self.runtime.stop(id: id)
                stopped += 1
            }
            return stopped == 1 ? "Stopped 1 service" : "Stopped \(stopped) services"
        }
    }

    /// Runs `container-compose up -d` for a single service within `project`.
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func upService(_ name: String, in project: ComposeProject) -> Task<Void, Never> {
        composeAction(project) { progress in
            try await self.composeRuntime.up(
                project: project,
                services: [name],
                rebuild: false,
                noCache: false,
                progress: progress
            )
        }
    }

    /// Stops a single running service container, stopping direct dependents first.
    ///
    /// Before stopping `name`, any other services in `project` that directly depend on
    /// `name` (per `project.serviceDependencies`) and are currently running are stopped
    /// first — direct dependents only (not transitive).
    ///
    /// Does NOT call `ComposeRuntime` — see `downProject(_:)` for the rationale.
    ///
    /// - Returns: The underlying `Task` (discardable).  Tests may `await` it to observe
    ///   post-action state without polling.
    @discardableResult
    func downService(_ name: String, in project: ComposeProject) -> Task<Void, Never> {
        // Snapshot containers on the MainActor before crossing into the Task closure.
        let statuses = Self.serviceStatuses(for: project, containers: containers)
        let statusMap = Dictionary(uniqueKeysWithValues: statuses.map { ($0.serviceName, $0) })

        // Collect direct dependents: services whose `depends_on` includes `name`.
        let dependents = project.serviceNames.filter { svc in
            svc != name && (project.serviceDependencies[svc] ?? []).contains(name)
        }
        // Stop running dependents first, then the target service.
        let stopOrder = dependents + [name]

        return composeAction(project) { _ in
            var stopped = 0
            for svc in stopOrder {
                if let status = statusMap[svc], status.state == .running {
                    try await self.runtime.stop(id: status.id)
                    stopped += 1
                }
            }
            return stopped == 1 ? "Stopped 1 service" : "Stopped \(stopped) services"
        }
    }

    // MARK: Compose action helper

    /// Shared scaffold for fire-and-forget compose actions that produce CLI output.
    ///
    /// Marks `project` as busy, launches a `Task`, and applies the error-visibility
    /// rule: on **success**, `lastComposeOutput` is set and a quiet refresh follows;
    /// on **failure**, the quiet refresh runs first (so the container list is up to
    /// date) and `handle(_:)` is called afterwards so the error message survives the
    /// refresh.  When the error is `.commandFailed`, its stderr is also stored in
    /// `lastComposeOutput` so the detail panel's Last Output section shows what the
    /// CLI printed.
    ///
    /// - Parameters:
    ///   - project: The compose project this action belongs to.
    ///   - work: An async throwing closure that shells out and returns trimmed stdout.
    /// - Returns: The underlying `Task` so call sites (e.g. unit tests) can `await`
    ///   completion without polling.  Production callers discard the return value.
    @discardableResult
    private func composeAction(
        _ project: ComposeProject,
        work: @escaping @Sendable (@escaping ComposeProgressHandler) async throws -> String
    ) -> Task<Void, Never> {
        guard !busyComposeProjects.contains(project.id) else {
            return Task {}
        }
        busyComposeProjects.insert(project.id)
        lastComposeOutput = ""
        return Task {
            do {
                let output = try await work { output in
                    Task { @MainActor [weak self] in
                        guard let self, self.busyComposeProjects.contains(project.id) else { return }
                        self.lastComposeOutput = output
                    }
                }
                lastComposeOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                errorMessage = nil
                busyComposeProjects.remove(project.id)
                await refresh(quiet: true)
            } catch {
                // Refresh first so container state is fresh before setting errorMessage.
                busyComposeProjects.remove(project.id)
                await refresh(quiet: true)
                // Surface the CLI stderr in the detail panel when available.
                if case .commandFailed(_, let stderr) = error as? ContainerRuntimeError {
                    lastComposeOutput = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                handle(error)
            }
        }
    }

    // MARK: Compose project management

    /// Registers the compose file at `url` and immediately reparses all projects.
    ///
    /// Does not touch containers — adding a project only updates the registered path list.
    func addComposeProject(url: URL) {
        composeStore.add(url)
        Task { await reloadComposeProjects() }
    }

    /// Removes `project` from the registered path list and immediately refreshes the list.
    ///
    /// Clears `selectedComposeProjectID` when it pointed at the removed project.
    /// Does not touch containers.
    func removeComposeProject(_ project: ComposeProject) {
        composeStore.remove(id: project.id)
        if selectedComposeProjectID == project.id {
            selectedComposeProjectID = nil
        }
        Task { await reloadComposeProjects() }
    }

    /// Reparses all registered compose files from disk and updates `composeProjects`.
    ///
    /// A lighter-weight alternative to a full `refresh()` — only the compose section
    /// is updated, leaving containers, images, and stats unchanged.
    private func reloadComposeProjects() async {
        let paths = composeStore.paths()
        let projects: [ComposeProject] = await Task.detached(priority: .utility) {
            paths.map { path -> ComposeProject in
                let fileURL = URL(fileURLWithPath: path)
                do {
                    return try ComposeFileParser.load(fileURL: fileURL)
                } catch {
                    let folderURL = fileURL.deletingLastPathComponent()
                    let projectName = ComposeFileParser.projectName(name: nil, folderURL: folderURL)
                    var stub = ComposeProject(
                        id: path,
                        fileURL: fileURL,
                        projectName: projectName,
                        displayName: folderURL.lastPathComponent,
                        serviceNames: [],
                        serviceImages: [:]
                    )
                    stub.isMissing = true
                    return stub
                }
            }
        }.value
        composeProjects = projects
    }
}
