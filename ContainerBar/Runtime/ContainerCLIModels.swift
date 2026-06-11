import Foundation

// MARK: - DTOs (mirrors Fixtures/list-all.json and Fixtures/stats.json)
// All fields are optional/lenient so unknown future keys don't break decoding.

/// Represents one element of `container list --all --format json`.
struct CLIContainerDTO: Decodable {
    let id: String
    let configuration: Configuration?
    let status: Status?         // NOTE: status is an OBJECT here, not a string

    struct Configuration: Decodable {
        let creationDate: String?
        let image: ImageRef?
        let initProcess: InitProcess?
        let publishedPorts: [PublishedPort]?
        let resources: Resources?

        struct ImageRef: Decodable {
            let reference: String?
        }

        struct InitProcess: Decodable {
            let executable: String?
            let arguments: [String]?
        }

        /// Port entry shape as observed in `list-all-ports.json`.
        struct PublishedPort: Decodable {
            let containerPort: Int?
            let count: Int?
            let hostAddress: String?
            let hostPort: Int?
            let proto: String?
        }

        struct Resources: Decodable {
            let cpus: Int?
            let memoryInBytes: Int64?
        }
    }

    struct Status: Decodable {
        let state: String?
        let startedDate: String?
    }
}

/// Represents one element of `container stats --format json --no-stream`.
/// All numeric fields are optional to tolerate missing keys in future CLI versions.
struct CLIStatsDTO: Decodable {
    let id: String
    let cpuUsageUsec: Int64?       // Cumulative — no percentage field in the CLI output
    let memoryUsageBytes: Int64?
    let memoryLimitBytes: Int64?
    let networkRxBytes: Int64?
    let networkTxBytes: Int64?
    let blockReadBytes: Int64?
    let blockWriteBytes: Int64?
    let numProcesses: Int?
}

// MARK: - ISO 8601 date parsing helpers

private extension ISO8601DateFormatter {
    /// Tries the plain format first, then fractional seconds, to handle both
    /// "2026-06-10T14:29:21Z" and "2026-06-10T14:29:21.123Z".
    static func flexibleParse(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

// MARK: - ByteCountFormatter helper

private func formattedBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: bytes)
}

// MARK: - Mapping: CLIContainerDTO → ContainerSummary

extension CLIContainerDTO {
    func toContainerSummary() -> ContainerSummary {
        // Image: strip the well-known docker.io/library/ prefix; keep other registries verbatim.
        let rawReference = configuration?.image?.reference ?? ""
        let image: String
        if rawReference.isEmpty {
            image = "(unknown)"
        } else if rawReference.hasPrefix("docker.io/library/") {
            image = String(rawReference.dropFirst("docker.io/library/".count))
        } else {
            image = rawReference
        }

        // State: absent status object → .unknown
        let state: ContainerState
        if let rawState = status?.state {
            state = ContainerState(rawValue: rawState) ?? .unknown
        } else {
            state = .unknown
        }

        // Command: executable + arguments joined with spaces
        let command: String?
        if let executable = configuration?.initProcess?.executable {
            let args = configuration?.initProcess?.arguments ?? []
            command = ([executable] + args).joined(separator: " ")
        } else {
            command = nil
        }

        // Dates
        let createdAt: Date? = configuration?.creationDate.flatMap(ISO8601DateFormatter.flexibleParse)
        let startedAt: Date? = status?.startedDate.flatMap(ISO8601DateFormatter.flexibleParse)

        // Ports: map each entry to "hostPort->containerPort/proto"; omit "0.0.0.0:" prefix
        // for brevity; include the host address for all other bind addresses.
        let ports: String?
        let portEntries = configuration?.publishedPorts ?? []
        if portEntries.isEmpty {
            ports = nil
        } else {
            let joined = portEntries.compactMap { entry -> String? in
                guard let hostPort = entry.hostPort, let containerPort = entry.containerPort else {
                    return nil
                }
                let proto = entry.proto.map { "/\($0)" } ?? ""
                let hostPrefix: String
                if let addr = entry.hostAddress, !addr.isEmpty, addr != "0.0.0.0" {
                    hostPrefix = "\(addr):\(hostPort)"
                } else {
                    hostPrefix = "\(hostPort)"
                }
                return "\(hostPrefix)->\(containerPort)\(proto)"
            }.joined(separator: ", ")
            ports = joined.isEmpty ? nil : joined
        }

        // imageReference: raw unstripped ref for in-use cross-referencing
        let imageReference: String? = {
            guard let ref = configuration?.image?.reference, !ref.isEmpty else { return nil }
            return ref
        }()

        return ContainerSummary(
            id: id,
            name: id,           // The CLI has no separate name field; id is the name
            image: image,
            state: state,
            status: state.displayName,
            command: command,
            createdAt: createdAt,
            startedAt: startedAt,
            ports: ports,
            cpuText: nil,       // Filled from stats by the view model later
            memoryText: nil,    // Filled from stats by the view model later
            imageReference: imageReference
        )
    }
}

// MARK: - Mapping: CLIStatsDTO → ContainerStats

extension CLIStatsDTO {
    func toContainerStats() -> ContainerStats {
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

        // Memory bytes: guard negative values that can't be represented as UInt64
        let memUsage: UInt64? = memoryUsageBytes.flatMap { $0 >= 0 ? UInt64($0) : nil }
        let memLimit: UInt64? = memoryLimitBytes.flatMap { $0 >= 0 ? UInt64($0) : nil }

        return ContainerStats(
            id: id,
            name: nil,
            cpuPercent: nil,            // Computed from two samples by the view model
            cpuUsageUsec: cpuUsageUsec, // Cumulative — passed through for delta computation
            memoryUsageBytes: memUsage,
            memoryLimitBytes: memLimit,
            memoryText: memoryText,
            networkText: networkText,
            blockIOText: blockIOText
        )
    }
}

// MARK: - CLIImageDTO (mirrors Fixtures/image-list.json)
// All fields are optional/lenient so unknown future keys don't break decoding.

/// Represents one element of `container image list --format json`
/// and `container image inspect <ref>`.
struct CLIImageDTO: Decodable {
    let id: String
    let configuration: Configuration?
    let variants: [Variant]?

    struct Configuration: Decodable {
        let name: String?
        let creationDate: String?
        // descriptor.size is the manifest size (~9 KB), NOT the image data size.
        // We decode it for completeness but never surface it in the UI.
        let descriptor: Descriptor?

        struct Descriptor: Decodable {
            let size: Int64?
        }
    }

    struct Variant: Decodable {
        let size: Int64?
        let platform: Platform?
        // config and digest are present in the real output but not used by the app.

        struct Platform: Decodable {
            let architecture: String?
            let os: String?
        }
    }
}

// MARK: - Name/tag parsing helpers (shared by CLIImageDTO.toImageSummary())

/// Splits a fully-qualified image reference into `(nameWithoutTag, tag)`.
///
/// The split point is the last `:` **after** the last `/`, so port numbers in
/// registry hosts (`registry:5000/foo`) are not mangled:
/// - `docker.io/library/alpine:latest` → `("docker.io/library/alpine", "latest")`
/// - `registry:5000/foo`              → `("registry:5000/foo", nil)`
/// - `registry:5000/app:v1`           → `("registry:5000/app", "v1")`
private func splitReference(_ reference: String) -> (name: String, tag: String?) {
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

// MARK: - Mapping: CLIImageDTO → ImageSummary

extension CLIImageDTO {
    func toImageSummary() -> ImageSummary {
        let reference = configuration?.name ?? id

        let (nameWithoutTag, tag) = splitReference(reference)
        let displayName = strippedDisplayName(from: nameWithoutTag)

        let digestShort = String(id.prefix(12))

        let createdAt: Date? = configuration?.creationDate
            .flatMap(ISO8601DateFormatter.flexibleParse)

        // sizeBytes is the sum of variant sizes; nil when variants are absent.
        // NOTE: configuration.descriptor.size is the manifest size (~9 KB), not
        // the image data size — never use that field for storage reporting.
        let sizeBytes: Int64? = variants.map { vs in
            vs.reduce(0) { $0 + ($1.size ?? 0) }
        }

        let architectures: [String] = (variants ?? []).compactMap { $0.platform?.architecture }

        return ImageSummary(
            id: id,
            reference: reference,
            displayName: displayName,
            tag: tag,
            digestShort: digestShort,
            createdAt: createdAt,
            sizeBytes: sizeBytes,
            architectures: architectures
        )
    }
}

// MARK: - FlexibleContainerDecoder

/// Decodes raw JSON strings produced by the `container` CLI into UI model types.
/// Strategy (§"JSON parsing strategy" in CHATGPT_HANDOFF.md):
///   1. Try strongly-typed decode.
///   2. On DecodingError, throw ContainerRuntimeError.decodingFailed with a bounded preview.
enum FlexibleContainerDecoder {
    /// Decodes `container list --all --format json` output into ContainerSummary values.
    static func decodeList(from json: String) throws -> [ContainerSummary] {
        guard let data = json.data(using: .utf8) else {
            let preview = String(json.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
        do {
            let dtos = try JSONDecoder().decode([CLIContainerDTO].self, from: data)
            return dtos.map { $0.toContainerSummary() }
        } catch is DecodingError {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
    }

    /// Decodes `container image list --format json` (or `container image inspect`) output
    /// into `ImageSummary` values.
    static func decodeImages(from json: String) throws -> [ImageSummary] {
        guard let data = json.data(using: .utf8) else {
            let preview = String(json.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
        do {
            let dtos = try JSONDecoder().decode([CLIImageDTO].self, from: data)
            return dtos.map { $0.toImageSummary() }
        } catch is DecodingError {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
    }

    /// Decodes `container stats --format json --no-stream` output into ContainerStats values.
    static func decodeStats(from json: String) throws -> [ContainerStats] {
        guard let data = json.data(using: .utf8) else {
            let preview = String(json.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
        do {
            let dtos = try JSONDecoder().decode([CLIStatsDTO].self, from: data)
            return dtos.map { $0.toContainerStats() }
        } catch is DecodingError {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ContainerRuntimeError.decodingFailed(raw: preview)
        }
    }
}
