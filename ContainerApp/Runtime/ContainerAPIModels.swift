import ContainerResource
import Foundation

// MARK: - Mapping from Apple's ContainerResource types to the flat UI models
//
// `ContainerAPIRuntime` receives the same Codable types the `container` CLI renders
// as JSON (`ManagedContainer`, `ContainerStats`, `ImageResource`), so the captured
// CLI output in `Fixtures/` still decodes into them and backs the mapping tests.

// MARK: - ByteCountFormatter helper

private func formattedBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: bytes)
}

private func formattedBytes(_ bytes: UInt64) -> String {
    formattedBytes(Int64(clamping: bytes))
}

// MARK: - Mapping: ManagedContainer → ContainerSummary

extension ManagedContainer {
    func toContainerSummary() -> ContainerSummary {
        // Image: strip the well-known docker.io/library/ prefix; keep other registries verbatim.
        let rawReference = configuration.image.reference
        let image: String
        if rawReference.isEmpty {
            image = "(unknown)"
        } else if rawReference.hasPrefix("docker.io/library/") {
            image = String(rawReference.dropFirst("docker.io/library/".count))
        } else {
            image = rawReference
        }

        // `stopping` (and any future runtime state) has no UI counterpart → .unknown
        let state = ContainerState(rawValue: status.state.rawValue) ?? .unknown

        // Command: executable + arguments joined with spaces
        let process = configuration.initProcess
        let command = process.executable.isEmpty
            ? nil
            : ([process.executable] + process.arguments).joined(separator: " ")

        // Ports: map each entry to "hostPort->containerPort/proto"; omit "0.0.0.0:" prefix
        // for brevity; include the host address for all other bind addresses.
        let ports: String?
        if configuration.publishedPorts.isEmpty {
            ports = nil
        } else {
            ports = configuration.publishedPorts.map { entry in
                let address = "\(entry.hostAddress)"
                let hostPrefix = address.isEmpty || address == "0.0.0.0"
                    ? "\(entry.hostPort)"
                    : "\(address):\(entry.hostPort)"
                return "\(hostPrefix)->\(entry.containerPort)/\(entry.proto.rawValue)"
            }.joined(separator: ", ")
        }

        return ContainerSummary(
            id: id,
            name: id,           // Containers have no separate name field; id is the name
            image: image,
            state: state,
            status: state.displayName,
            command: command,
            createdAt: configuration.creationDate,
            startedAt: status.startedDate,
            ports: ports,
            cpuText: nil,       // Filled from stats by the view model later
            memoryText: nil,    // Filled from stats by the view model later
            imageReference: rawReference.isEmpty ? nil : rawReference
        )
    }
}

// MARK: - Mapping: ContainerResource.ContainerStats → ContainerStats

extension ContainerResource.ContainerStats {
    func toContainerStats() -> ContainerApp.ContainerStats {
        // Memory text: "usage / limit"
        let memoryText: String?
        if let usage = memoryUsageBytes, let limit = memoryLimitBytes {
            memoryText = "\(formattedBytes(usage)) / \(formattedBytes(limit))"
        } else if let usage = memoryUsageBytes {
            memoryText = formattedBytes(usage)
        } else {
            memoryText = nil
        }

        // Network text: "↓ rx / ↑ tx"
        let networkText: String?
        if let rx = networkRxBytes, let tx = networkTxBytes {
            networkText = "↓ \(formattedBytes(rx)) / ↑ \(formattedBytes(tx))"
        } else {
            networkText = nil
        }

        // Block I/O text: "read R / written W"
        let blockIOText: String?
        if let read = blockReadBytes, let write = blockWriteBytes {
            blockIOText = "read \(formattedBytes(read)) / written \(formattedBytes(write))"
        } else {
            blockIOText = nil
        }

        return ContainerApp.ContainerStats(
            id: id,
            name: nil,
            cpuPercent: nil,            // Computed from two samples by the view model
            cpuUsageUsec: cpuUsageUsec.map { Int64(clamping: $0) },  // Cumulative, for delta computation
            memoryUsageBytes: memoryUsageBytes,
            memoryLimitBytes: memoryLimitBytes,
            memoryText: memoryText,
            networkText: networkText,
            blockIOText: blockIOText
        )
    }
}

// MARK: - Name/tag parsing helpers

/// Splits a fully-qualified image reference into `(nameWithoutTag, tag)`.
///
/// The split point is the last `:` **after** the last `/`, so port numbers in
/// registry hosts (`registry:5000/foo`) are not mangled:
/// - `docker.io/library/alpine:latest` → `("docker.io/library/alpine", "latest")`
/// - `registry:5000/foo`              → `("registry:5000/foo", nil)`
/// - `registry:5000/app:v1`           → `("registry:5000/app", "v1")`
func splitImageReference(_ reference: String) -> (name: String, tag: String?) {
    // Find the last path separator so we only look for `:` after it.
    let lastSlashIdx = reference.lastIndex(of: "/") ?? reference.startIndex
    let afterLastSlash = reference[lastSlashIdx...]
    guard let colonIdx = afterLastSlash.lastIndex(of: ":") else {
        return (reference, nil)
    }
    let name = String(reference[reference.startIndex..<colonIdx])
    let tag  = String(reference[reference.index(after: colonIdx)...])
    return (name, tag.isEmpty ? nil : tag)
}

/// Strips the `docker.io/library/` prefix for display, leaving other registries intact.
private func strippedDisplayName(from nameWithoutTag: String) -> String {
    let prefix = "docker.io/library/"
    if nameWithoutTag.hasPrefix(prefix) {
        return String(nameWithoutTag.dropFirst(prefix.count))
    }
    return nameWithoutTag
}

/// `true` when `reference` is one of the runtime's own images (the VM init filesystem
/// or the builder), which `container image list` hides and which must not be deleted.
///
/// Compares names without tags: the library's default configuration names the init
/// image of the version the app was built against, while the installed runtime may
/// use an older or newer tag of the same image.
func isInfrastructureImage(_ reference: String, infrastructureReferences: [String]) -> Bool {
    let name = splitImageReference(reference).name
    return infrastructureReferences.contains { splitImageReference($0).name == name }
}

// MARK: - Mapping: ImageResource → ImageSummary

extension ImageResource {
    func toImageSummary() -> ImageSummary {
        let reference = configuration.name
        let (nameWithoutTag, tag) = splitImageReference(reference)

        // The library reports the epoch when no variant carries a creation date.
        let createdAt: Date? = configuration.creationDate.timeIntervalSince1970 > 0
            ? configuration.creationDate
            : nil

        return ImageSummary(
            id: id,
            reference: reference,
            displayName: strippedDisplayName(from: nameWithoutTag),
            tag: tag,
            digestShort: String(id.prefix(12)),
            createdAt: createdAt,
            // Real on-disk weight: index descriptor + config + layers, per variant.
            sizeBytes: variants.reduce(0) { $0 + $1.size },
            architectures: variants.map { $0.platform.architecture }
        )
    }
}

// MARK: - JSON rendering

/// Renders `value` the way `container inspect` / `container image inspect` print it:
/// pretty-printed, sorted keys, ISO 8601 dates, unescaped slashes.
func renderInspectJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
