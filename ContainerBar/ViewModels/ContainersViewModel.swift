import Observation

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

    let runtime: any ContainerRuntime

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

    var filteredContainers: [ContainerSummary] {
        switch sidebarSelection {
        case .all, .none:
            return containers
        case .running:
            return containers.filter { $0.state == .running }
        case .stopped:
            return containers.filter { $0.state != .running }
        case .images, .settings:
            return containers
        }
    }

    // MARK: Methods

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedContainers = runtime.listContainers()
            async let fetchedStatus = runtime.systemStatus()
            async let fetchedStats = runtime.stats(id: nil)
            containers = try await fetchedContainers
            systemStatus = try await fetchedStatus
            stats = try await fetchedStats
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshStats() async {
        do {
            stats = try await runtime.stats(id: nil)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            errorMessage = error.localizedDescription
        }
    }

    func kill(_ container: ContainerSummary) async {
        do {
            try await runtime.kill(id: container.id)
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func startSystem() async {
        do {
            try await runtime.startSystem()
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSystem() async {
        do {
            try await runtime.stopSystem()
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ container: ContainerSummary) {
        selectedContainerID = container.id
    }

    /// TODO: Phase 3 — launch Terminal.app with `container exec -it <id> /bin/sh`
    func openShell(_ container: ContainerSummary) {
        // no-op until Phase 3
    }
}
