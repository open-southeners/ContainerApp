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

        /// Lenient port entry — real populated shape not yet sampled.
        /// TODO: update once a fixture with non-empty publishedPorts is captured.
        struct PublishedPort: Decodable {
            let hostPort: Int?
            let containerPort: Int?
            let `protocol`: String?
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

        // Ports: publishedPorts is an empty array in all current fixtures.
        // TODO: update this mapping once a fixture with non-empty publishedPorts is captured
        //       so the exact populated shape can be verified.
        let ports: String?
        let portEntries = configuration?.publishedPorts ?? []
        if portEntries.isEmpty {
            ports = nil
        } else {
            let joined = portEntries.compactMap { entry -> String? in
                guard let host = entry.hostPort, let container = entry.containerPort else {
                    return nil
                }
                let proto = entry.protocol.map { "/\($0)" } ?? ""
                return "\(host)->\(container)\(proto)"
            }.joined(separator: ", ")
            ports = joined.isEmpty ? nil : joined
        }

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
            memoryText: nil     // Filled from stats by the view model later
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
            // TODO: Phase 4 — cpuUsageUsec is cumulative; computing a percentage requires
            //       two samples and a time delta. Leave nil until then.
            cpuPercent: nil,
            memoryUsageBytes: memUsage,
            memoryLimitBytes: memLimit,
            memoryText: memoryText,
            networkText: networkText,
            blockIOText: blockIOText
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
