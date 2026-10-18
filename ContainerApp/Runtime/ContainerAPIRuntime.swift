import ContainerAPIClient
import ContainerizationError
import ContainerizationOCI
import ContainerPersistence
import ContainerResource
import Foundation
import SystemPackage

// MARK: - ContainerAPIRuntime

/// A `ContainerRuntime` that talks to the container system's `container-apiserver`
/// over XPC through Apple's `ContainerAPIClient` library — the same client the
/// `container` CLI is built on — instead of spawning the CLI and parsing its output.
///
/// Containers, images and stats are shared with the CLI and `container-compose`
/// because they all go through the same apiserver.  Starting and stopping the
/// system itself stays on the CLI (`ContainerSystemCLI`): that registers the
/// installed apiserver with launchd rather than calling it.
///
/// Error mapping: an XPC connection failure means the apiserver isn't registered,
/// which reads as `.systemNotRunning` when the CLI is installed and `.cliNotFound`
/// when it isn't; a `notFound` anywhere in the error's cause chain becomes
/// `.notFound(id:)`; everything else becomes `.requestFailed(message:)`.
final class ContainerAPIRuntime: ContainerRuntime {

    // MARK: Stored properties

    private let client = ContainerClient()
    private let systemCLI: ContainerSystemCLI

    // MARK: Init

    init(systemCLI: ContainerSystemCLI = ContainerSystemCLI()) {
        self.systemCLI = systemCLI
    }

    // MARK: - Error mapping

    /// Runs `body`, translating library errors into `ContainerRuntimeError`.
    /// Pass the `id` when the request targets a specific container or image so a
    /// "not found" can be reported as `.notFound(id:)`.
    private func request<T>(id: String? = nil, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as ContainerRuntimeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw await map(error, id: id)
        }
    }

    private func map(_ error: any Error, id: String?) async -> ContainerRuntimeError {
        switch Self.classify(error) {
        case .connectionFailed:
            // The apiserver isn't registered with launchd: stopped, or never installed.
            do {
                _ = try await systemCLI.resolvedBinaryURL()
                return .systemNotRunning
            } catch {
                return .cliNotFound
            }
        case .notFound(let message):
            if let id { return .notFound(id: id) }
            return .requestFailed(message: message)
        case .failed(let message):
            return .requestFailed(message: message)
        }
    }

    enum ErrorClass: Equatable {
        case connectionFailed
        case notFound(message: String)
        case failed(message: String)
    }

    /// Pure classification of a library error by walking its cause chain.
    /// The client wraps server-side errors (e.g. `notFound`) as the `cause` of a
    /// generic "failed to …" error, so the outermost code alone isn't enough.
    nonisolated static func classify(_ error: any Error) -> ErrorClass {
        var messages: [String] = []
        var isNotFound = false
        var current: (any Error)? = error
        while let next = current {
            guard let containerError = next as? ContainerizationError else {
                messages.append(String(describing: next))
                break
            }
            if containerError.isCode(.interrupted)
                || containerError.message.contains("XPC connection error")
            {
                return .connectionFailed
            }
            if containerError.isCode(.notFound) {
                isNotFound = true
            }
            messages.append(containerError.message)
            current = containerError.cause
        }
        let message = messages.joined(separator: ": ")
        return isNotFound ? .notFound(message: message) : .failed(message: message)
    }

    // MARK: - Helpers

    /// Containers created by `container machine` are listed by the apiserver but
    /// hidden by every CLI command; the app hides them the same way.
    private func containerSnapshots(status: RuntimeStatus? = nil) async throws -> [ContainerSnapshot] {
        try await client.list(filters: ContainerListFilters(status: status).withoutMachines())
    }

    private func snapshot(id: String) async throws -> ContainerSnapshot {
        guard let snapshot = try await client.list(filters: ContainerListFilters(ids: [id])).first else {
            throw ContainerRuntimeError.notFound(id: id)
        }
        return snapshot
    }

    /// The installed system's configuration (`config.toml` in the app root, then the
    /// install root), as the CLI loads it.  Used to normalize image references and
    /// to recognize the runtime's own images.
    private func systemConfig() async throws -> ContainerSystemConfig {
        let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let appRoot = FilePath(health.appRoot.path(percentEncoded: false))
        let installRoot = FilePath(health.installRoot.path(percentEncoded: false))
        return try await ConfigurationLoader.load(configurationFiles: [
            ConfigurationLoader.configurationFile(in: appRoot, of: .appRoot),
            ConfigurationLoader.configurationFile(in: installRoot, of: .installRoot),
        ])
    }

    private func infrastructureReferences(_ config: ContainerSystemConfig) -> [String] {
        [config.vminit.image, config.build.image]
    }

    /// Images as `container image list` shows them: the runtime's own images hidden.
    private func userImages(_ config: ContainerSystemConfig) async throws -> [ClientImage] {
        let references = infrastructureReferences(config)
        return try await ClientImage.list().filter {
            !isInfrastructureImage($0.reference, infrastructureReferences: references)
        }
    }

    private func image(reference: String, config: ContainerSystemConfig) async throws -> ClientImage {
        let result = try await ClientImage.get(names: [reference], containerSystemConfig: config)
        guard let image = result.images.first else {
            throw ContainerRuntimeError.notFound(id: reference)
        }
        return image
    }

    /// Untagged images are stored under digest references (`name@sha256:…`), so
    /// this parses the reference rather than splitting on `:`.
    private static func hasTag(_ reference: String) -> Bool {
        guard let tag = try? ContainerizationOCI.Reference.parse(reference).tag else { return false }
        return !tag.isEmpty
    }

    private static func reclaimedSummary(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "Reclaimed \(formatter.string(fromByteCount: Int64(clamping: bytes))) in disk space"
    }

    // MARK: - ContainerRuntime

    func listContainers() async throws -> [ContainerSummary] {
        try await request {
            try await containerSnapshots().map { ManagedContainer($0).toContainerSummary() }
        }
    }

    /// The container rendered as `container inspect <id>` prints it.
    func inspect(id: String) async throws -> String {
        try await request(id: id) {
            try renderInspectJSON([ManagedContainer(try await snapshot(id: id))])
        }
    }

    /// The last `lines` lines of the container's stdio log, like `container logs -n`.
    func logs(id: String, lines: Int) async throws -> String {
        try await request(id: id) {
            // [0] is the container's stdio log, [1] the VM boot log.
            let handles = try await client.logs(id: id)
            defer { handles.forEach { try? $0.close() } }
            guard let handle = handles.first else { return "" }
            return try Self.tail(handle, lines: lines).joined(separator: "\n")
        }
    }

    /// Reads backwards from the end of `handle` in 1 KB chunks until `lines`
    /// non-empty lines are collected (the CLI's `logs -n` algorithm).
    nonisolated static func tail(_ handle: FileHandle, lines count: Int) throws -> [String] {
        var buffer = Data()
        var offset = try handle.seekToEnd()
        var lines: [String] = []
        while offset > 0, lines.count < count {
            let readSize = min(1024, offset)
            offset -= readSize
            try handle.seek(toOffset: offset)
            buffer.insert(contentsOf: handle.readData(ofLength: Int(readSize)), at: 0)
            if let chunk = String(data: buffer, encoding: .utf8) {
                lines = chunk.components(separatedBy: .newlines).filter { !$0.isEmpty }
            }
        }
        return Array(lines.suffix(count))
    }

    /// Stats for one container, or for every running container when `id` is nil.
    /// A container that stops between listing and sampling is left out rather than
    /// failing the whole sample.
    func stats(id: String?) async throws -> [ContainerApp.ContainerStats] {
        try await request(id: id) {
            if let id {
                return [try await client.stats(id: id).toContainerStats()]
            }
            let running = try await containerSnapshots(status: .running)
            return await withTaskGroup(of: ContainerApp.ContainerStats?.self) { group in
                for snapshot in running {
                    group.addTask { [client] in
                        try? await client.stats(id: snapshot.id).toContainerStats()
                    }
                }
                var collected: [ContainerApp.ContainerStats] = []
                for await stats in group {
                    if let stats { collected.append(stats) }
                }
                return collected
            }
        }
    }

    /// Starts the container detached, like `container start <id>`: bootstraps its
    /// init process with no attached stdio, then starts it.
    func start(id: String) async throws {
        try await request(id: id) {
            let container = try await snapshot(id: id)
            guard container.status != .running else { return }

            for mount in container.configuration.mounts where mount.isVirtiofs {
                guard FileManager.default.fileExists(atPath: mount.source) else {
                    throw ContainerRuntimeError.requestFailed(
                        message: "mount source path '\(mount.source)' does not exist"
                    )
                }
            }

            do {
                let process = try await client.bootstrap(id: id, stdio: [nil, nil, nil])
                try await process.start()
            } catch {
                // Leave the container stopped rather than half-bootstrapped.
                try? await client.stop(id: id)
                throw error
            }
        }
    }

    /// Sends the stop signal and waits up to 5 seconds before killing,
    /// like `container stop <id>`.
    func stop(id: String) async throws {
        try await request(id: id) {
            try await client.stop(id: id, opts: .default)
        }
    }

    /// Sends `SIGKILL`, like `container kill <id>`.
    func kill(id: String) async throws {
        try await request(id: id) {
            try await client.kill(id: id, signal: "KILL")
        }
    }

    func delete(id: String) async throws {
        try await request(id: id) {
            try await client.delete(id: id, force: false)
        }
    }

    /// Deletes every stopped container, like `container prune`.  Containers that
    /// fail to delete are reported together after the rest have been removed.
    func pruneContainers() async throws {
        try await request {
            var failures: [String] = []
            for container in try await containerSnapshots(status: .stopped) {
                do {
                    try await client.delete(id: container.id, force: false)
                } catch {
                    failures.append(container.id)
                }
            }
            if !failures.isEmpty {
                throw ContainerRuntimeError.requestFailed(
                    message: "failed to delete \(failures.joined(separator: ", "))"
                )
            }
        }
    }

    func startSystem() async throws {
        try await systemCLI.startSystem()
    }

    func stopSystem() async throws {
        try await systemCLI.stopSystem()
    }

    /// Pings the apiserver.  A stopped system reads as `.stopped` rather than an
    /// error; a missing installation still throws `.cliNotFound`.
    func systemStatus() async throws -> ContainerSystemStatus {
        do {
            return try await request {
                _ = try await ClientHealthCheck.ping(timeout: .seconds(5))
                return .running
            }
        } catch ContainerRuntimeError.systemNotRunning {
            return .stopped
        } catch ContainerRuntimeError.requestFailed(let message) {
            return .unknown(message)
        }
    }

    // MARK: - Image management

    func listImages() async throws -> [ImageSummary] {
        try await request {
            let config = try await systemConfig()
            var summaries: [ImageSummary] = []
            for image in try await userImages(config) {
                summaries.append(try await image.toImageResource(containerSystemConfig: config).toImageSummary())
            }
            return summaries
        }
    }

    /// The image rendered as `container image inspect <reference>` prints it.
    func inspectImage(reference: String) async throws -> String {
        try await request(id: reference) {
            let config = try await systemConfig()
            let resource = try await image(reference: reference, config: config)
                .toImageResource(containerSystemConfig: config)
            return try renderInspectJSON([resource])
        }
    }

    /// Removes the image and garbage-collects blobs nothing references any more,
    /// like `container image delete <reference>`.  The runtime's own images are
    /// refused.
    func deleteImage(reference: String) async throws {
        try await request(id: reference) {
            let config = try await systemConfig()
            let image = try await image(reference: reference, config: config)
            guard !isInfrastructureImage(image.reference, infrastructureReferences: infrastructureReferences(config)) else {
                throw ContainerRuntimeError.requestFailed(
                    message: "\(reference) is used by the container system and can't be deleted"
                )
            }
            try await ClientImage.delete(reference: image.reference, garbageCollect: false)
            _ = try await ClientImage.cleanUpOrphanedBlobs()
        }
    }

    /// Removes dangling (untagged) images and unreferenced blobs, like
    /// `container image prune`, and returns its summary line.
    func pruneImages() async throws -> String {
        try await request {
            let config = try await systemConfig()
            for image in try await userImages(config) where !Self.hasTag(image.reference) {
                try? await ClientImage.delete(reference: image.reference, garbageCollect: false)
            }
            let (_, reclaimed) = try await ClientImage.cleanUpOrphanedBlobs()
            return Self.reclaimedSummary(reclaimed)
        }
    }
}
