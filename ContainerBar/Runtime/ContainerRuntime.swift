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

    // MARK: - Image management

    /// `container image list --format json` decoded into `ImageSummary` values.
    func listImages() async throws -> [ImageSummary]
    /// `container image inspect <reference>` — returns the raw pretty-printed JSON string.
    /// Throws `.notFound(id:)` when the reference is unknown to the runtime.
    func inspectImage(reference: String) async throws -> String
    /// `container image delete <reference>` — removes the image from the local store.
    func deleteImage(reference: String) async throws
    /// `container image prune` — removes dangling images and returns the CLI summary line
    /// (e.g. `"Reclaimed Zero KB in disk space"`).
    func pruneImages() async throws -> String
}
