/// Abstraction over a container backend (CLI or native Swift).
/// All methods are async throws so the caller never blocks the main actor.
protocol ContainerRuntime: Sendable {
    func listContainers() async throws -> [ContainerSummary]
    func inspect(id: String) async throws -> String
    func logs(id: String, lines: Int) async throws -> String
    func stats(id: String?) async throws -> [ContainerStats]
    func stop(id: String) async throws
    func kill(id: String) async throws
    func delete(id: String) async throws
    /// Removes all stopped containers (`container prune`).
    func pruneContainers() async throws
    func startSystem() async throws
    func stopSystem() async throws
    func systemStatus() async throws -> ContainerSystemStatus
}
