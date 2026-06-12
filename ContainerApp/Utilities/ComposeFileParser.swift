import Foundation
import Yams

// MARK: - ComposeError

/// Errors thrown by `ComposeFileParser`.
enum ComposeError: Error, Sendable {
    /// The YAML could not be decoded or is structurally invalid.
    /// `message` contains a bounded preview of the raw content to aid debugging.
    case parseFailed(String)
}

// MARK: - Internal YAML decode types

/// Minimal compose-file skeleton — only the keys the app uses are decoded.
/// All fields are optional/lenient so unknown keys in the file don't break parsing
/// (same leniency policy as `CLIContainerDTO`).
private struct ComposeFileStub: Decodable {
    let name: String?
    /// Service values can be `null` (bare key) — hence the double-optional.
    let services: [String: ServiceStub?]?
}

/// Minimal per-service stub containing the fields used by the app.
private struct ServiceStub: Decodable {
    let image: String?
    let container_name: String?
    let depends_on: DependsOn?

    /// A `Decodable` sink that accepts any JSON/YAML value shape — object, string,
    /// bool, null, etc. — by simply not reading from the decoder at all.
    ///
    /// Used as the map-value type for `depends_on`'s map form so that mixed-type
    /// condition objects like `{ condition: service_healthy, restart: true }` do not
    /// cause a decode failure (a plain `[String: String]` would throw on a Bool value).
    struct IgnoredValue: Decodable {
        init(from decoder: any Decoder) throws {
            // Intentionally empty: we only need the map keys, not the values.
        }
    }

    /// `depends_on:` accepts two YAML forms:
    ///  - Array form: `depends_on: [db, cache]`
    ///  - Map form:   `depends_on: { db: { condition: service_healthy } }`
    ///
    /// Both forms decode to the same underlying list of dependency names (keys only
    /// for the map form).  Missing or empty `depends_on` decodes to an empty list.
    ///
    /// Map values are decoded as `IgnoredValue` so that mixed types within the
    /// condition object (e.g. `restart: true`) do not cause a decode failure.
    enum DependsOn: Decodable {
        case list([String])
        case map([String: IgnoredValue])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Try the array form first (most common); fall back to the map form.
            if let list = try? container.decode([String].self) {
                self = .list(list)
            } else {
                let map = try container.decode([String: IgnoredValue].self)
                self = .map(map)
            }
        }

        /// The service names this entry depends on, regardless of which form was used.
        var names: [String] {
            switch self {
            case .list(let names): return names
            case .map(let dict):   return Array(dict.keys).sorted()
            }
        }
    }
}

// MARK: - ComposeFileParser

/// Parses a docker-compose YAML file into a `ComposeProject`.
///
/// The parser is kept pure (no side effects other than throwing): `parse(text:fileURL:)`
/// is the testable core; `load(fileURL:)` is a thin wrapper that reads the file from disk.
enum ComposeFileParser {

    // MARK: Public API

    /// Parses compose YAML `text` as if it were located at `fileURL`.
    ///
    /// `fileURL` is used only for project-name derivation and to populate
    /// `ComposeProject.fileURL` / `ComposeProject.id` — the text is not re-read from disk.
    ///
    /// - Throws: `ComposeError.parseFailed` when the YAML is malformed or has no `services:` key.
    static func parse(text: String, fileURL: URL) throws -> ComposeProject {
        let stub: ComposeFileStub
        do {
            stub = try YAMLDecoder().decode(ComposeFileStub.self, from: text)
        } catch {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ComposeError.parseFailed(preview)
        }

        // `services:` key must be present (may be empty, but nil means the file
        // is not a compose file or has no services block at all).
        guard let servicesMap = stub.services else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ComposeError.parseFailed("Missing 'services:' key — \(preview)")
        }

        let folderURL = fileURL.deletingLastPathComponent()
        let projectName = Self.projectName(name: stub.name, folderURL: folderURL)
        let displayName = stub.name ?? folderURL.lastPathComponent

        // Derive service names in YAML declaration order using Yams' Node-level API,
        // which preserves key insertion order unlike the Dictionary-backed YAMLDecoder.
        // If Node composition fails (shouldn't happen since YAMLDecoder already succeeded),
        // fall back to the alphabetically-sorted keys for deterministic output.
        let serviceNames = Self.orderedServiceNames(from: text, fallback: servicesMap.keys.sorted())

        // Build raw image map — null service bodies (nil ServiceStub) have no image.
        var serviceImages: [String: String] = [:]
        var serviceContainerNames: [String: String] = [:]
        for (name, stubOpt) in servicesMap {
            if let image = stubOpt?.image {
                serviceImages[name] = image
            }
            if let containerName = stubOpt?.container_name, !containerName.isEmpty {
                serviceContainerNames[name] = containerName
            }
        }

        // Build dependency map — only services that have a non-empty depends_on entry.
        var serviceDependencies: [String: [String]] = [:]
        for (name, stubOpt) in servicesMap {
            if let deps = stubOpt?.depends_on?.names, !deps.isEmpty {
                serviceDependencies[name] = deps
            }
        }

        return ComposeProject(
            id: fileURL.standardizedFileURL.path,
            fileURL: fileURL,
            projectName: projectName,
            displayName: displayName,
            serviceNames: serviceNames,
            serviceImages: serviceImages,
            serviceContainerNames: serviceContainerNames,
            serviceDependencies: serviceDependencies
        )
    }

    /// Reads the file at `fileURL` from disk and delegates to `parse(text:fileURL:)`.
    ///
    /// Sets `isMissing = true` on the returned project when the file cannot be read,
    /// returning a stub so callers can still show the row with a warning.
    static func load(fileURL: URL) throws -> ComposeProject {
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Return a stub with isMissing so the project row stays visible.
            let id = fileURL.standardizedFileURL.path
            let folderURL = fileURL.deletingLastPathComponent()
            let projectName = Self.projectName(name: nil, folderURL: folderURL)
            let displayName = folderURL.lastPathComponent
            var stub = ComposeProject(
                id: id,
                fileURL: fileURL,
                projectName: projectName,
                displayName: displayName,
                serviceNames: [],
                serviceImages: [:]
            )
            stub.isMissing = true
            return stub
        }
        return try parse(text: text, fileURL: fileURL)
    }

    // MARK: Project-name derivation

    /// Derives the compose project name, mirroring `container-compose`'s `deriveProjectName`.
    ///
    /// - Returns `name` when non-nil and non-empty (the compose file's top-level `name:` wins).
    /// - Otherwise, returns `folderURL.lastPathComponent` with every `.` replaced by `_`.
    ///
    /// This is kept as a `static func` so tests can pin sanitization independently of
    /// full file parsing.
    static func projectName(name: String?, folderURL: URL) -> String {
        if let name, !name.isEmpty {
            return name
        }
        return folderURL.lastPathComponent.replacingOccurrences(of: ".", with: "_")
    }

    // MARK: Stop-order computation

    /// Returns services in safe stop order: dependents before their dependencies
    /// (reverse topological sort).
    ///
    /// For example, if `web` depends on `db`, this returns `["web", "db"]` — web
    /// is stopped before db.  Services with no dependency relationships are emitted in
    /// reverse `serviceNames` order (i.e. reverse YAML declaration order).
    ///
    /// Unknown dependency names referenced in `dependencies` (names absent from
    /// `serviceNames`) are silently ignored — they are not inserted into the output.
    ///
    /// Cycles are broken deterministically: when a cycle is detected, the cycle's
    /// members are emitted in reverse `serviceNames` order and the algorithm continues
    /// with the remaining services.  The output is always a permutation of `serviceNames`.
    ///
    /// - Parameters:
    ///   - serviceNames: Services in YAML declaration order (determines tie-break order).
    ///   - dependencies: Map of `serviceName → [dependencyNames]`.
    /// - Returns: All services from `serviceNames`, each appearing exactly once.
    static func stopOrder(
        serviceNames: [String],
        dependencies: [String: [String]]
    ) -> [String] {
        let nameSet = Set(serviceNames)

        // Build a clean adjacency list: for each service, list its direct dependencies
        // that are actually part of this project (ignore unknown names).
        var deps: [String: [String]] = [:]
        for name in serviceNames {
            let known = (dependencies[name] ?? []).filter { nameSet.contains($0) }
            deps[name] = known
        }

        // Kahn's algorithm for topological sort with cycle detection.
        // We want dependents before their dependencies, so we sort on the reverse graph:
        // an edge "A depends on B" means "stop A before B" — i.e. B has in-degree 1
        // from A in the stop-order graph.  In Kahn's on the *original* dep graph, nodes
        // with in-degree 0 (nothing depends on them) are emitted first.
        //
        // "Stop A before B" is equivalent to topological sort of: A → B (A before B),
        // which is *not* the reverse — it IS the dependency direction (dependents first).
        // So we run Kahn's on the dependency graph as-is.

        // Compute in-degree: number of other services that depend on each service.
        var inDegree: [String: Int] = Dictionary(uniqueKeysWithValues: serviceNames.map { ($0, 0) })
        for name in serviceNames {
            for dep in deps[name] ?? [] {
                inDegree[dep, default: 0] += 1
            }
        }

        // Deterministic tie-breaking: use the *reverse* of serviceNames index so that
        // among services with equal in-degree, those declared later in the YAML file
        // sort first.  This matches the "reverse file order" expectation for no-dep cases.
        let indexMap: [String: Int] = Dictionary(
            uniqueKeysWithValues: serviceNames.enumerated().map { ($0.element, $0.offset) }
        )

        // Queue: services with in-degree 0 (nothing currently depends on them — stop first).
        // Sort by descending declaration index (later in file = first to stop) for determinism.
        var queue = serviceNames
            .filter { inDegree[$0]! == 0 }
            .sorted { (indexMap[$0] ?? 0) > (indexMap[$1] ?? 0) }

        var result: [String] = []
        var visited: Set<String> = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard !visited.contains(node) else { continue }
            visited.insert(node)
            result.append(node)

            // For each dependency of `node`, decrement its in-degree.
            // When it reaches 0, no remaining dependents need to be stopped first → enqueue.
            let nodeDeps = (deps[node] ?? []).sorted { (indexMap[$0] ?? 0) > (indexMap[$1] ?? 0) }
            for dep in nodeDeps {
                inDegree[dep, default: 0] -= 1
                if inDegree[dep]! == 0 {
                    queue.append(dep)
                }
            }
        }

        // Any services not yet visited are part of a cycle.  Emit them in reverse
        // declaration order for deterministic output.
        let cycleNodes = serviceNames
            .filter { !visited.contains($0) }
            .reversed()
        result.append(contentsOf: cycleNodes)

        return result
    }

    // MARK: Private helpers

    /// Uses Yams' Node-level API to extract the ordered keys of the top-level
    /// `services:` mapping, preserving the original YAML declaration order.
    ///
    /// Returns `fallback` when the Node cannot be composed or has no `services`
    /// mapping (should not happen if `YAMLDecoder` already succeeded on the same text).
    private static func orderedServiceNames(from text: String, fallback: [String]) -> [String] {
        guard
            let root = try? Yams.compose(yaml: text),
            let rootMapping = root.mapping,
            let servicesNode = rootMapping["services"],
            let servicesMapping = servicesNode.mapping
        else {
            return fallback
        }

        // Keys are in document order — extract the string values.
        let ordered = Array(servicesMapping.keys.compactMap { $0.string })
        // Guard against an empty result (e.g. all keys were non-scalar nodes).
        return ordered.isEmpty ? fallback : ordered
    }
}
