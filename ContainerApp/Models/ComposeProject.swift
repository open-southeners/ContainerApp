import Foundation

/// A registered docker-compose project, parsed from a compose YAML file on disk.
///
/// `id` is the absolute path of the compose file, which serves as both a stable
/// table identity and the key used by `ComposeProjectStore`.
struct ComposeProject: Identifiable, Hashable, Sendable {
    /// Absolute path of the compose file — stable identity and store key.
    let id: String

    /// File URL of the compose file.
    let fileURL: URL

    /// Derived project name used when constructing container IDs (`<project>-<service>`).
    /// Equals the top-level `name:` field when present; otherwise the folder name with
    /// `.` replaced by `_` (mirrors `container-compose`'s `deriveProjectName`).
    let projectName: String

    /// Human-readable project name for the UI.
    /// Equals the top-level `name:` field when present; otherwise the folder name verbatim
    /// (dots are NOT replaced — this is for display only).
    let displayName: String

    /// Service names in YAML declaration order.
    let serviceNames: [String]

    /// Raw image reference per service, as written in the compose file.
    /// May contain unresolved variable expressions such as `${TAG:-latest}`.
    /// Used for display only — never passed to the CLI.
    let serviceImages: [String: String]

    /// Explicit `container_name` per service, when declared in the compose file.
    /// Services without an override use container-compose's default
    /// `<project>-<service>` identifier.
    let serviceContainerNames: [String: String]

    /// Direct dependencies per service, as declared by `depends_on:` in the compose file.
    /// Keys are service names; values are the service names that key depends on.
    /// Both the string-array form (`depends_on: [db, cache]`) and the map form
    /// (`depends_on: { db: { condition: service_healthy } }`) are parsed — keys only
    /// for the map form.  Services with no `depends_on:` entry are absent from the map.
    let serviceDependencies: [String: [String]]

    /// `true` when the registered file could not be found on disk at last parse.
    /// The row shows a warning icon; all actions except Remove are disabled.
    var isMissing: Bool = false

    init(
        id: String,
        fileURL: URL,
        projectName: String,
        displayName: String,
        serviceNames: [String],
        serviceImages: [String: String],
        serviceContainerNames: [String: String] = [:],
        serviceDependencies: [String: [String]] = [:]
    ) {
        self.id = id
        self.fileURL = fileURL
        self.projectName = projectName
        self.displayName = displayName
        self.serviceNames = serviceNames
        self.serviceImages = serviceImages
        self.serviceContainerNames = serviceContainerNames
        self.serviceDependencies = serviceDependencies
    }
}

/// The live status of one service within a compose project, derived by matching
/// its explicit `container_name` or default `<project>-<service>` identifier.
struct ComposeServiceStatus: Identifiable, Hashable, Sendable {
    /// Actual container id expected for this service.
    let id: String

    /// Service name as declared in the compose file.
    let serviceName: String

    /// Raw image reference from the compose YAML (may contain `${VAR:-default}`).
    /// `nil` when the service had a null body or no `image:` key.
    let image: String?

    /// State of the matching container in the live container list.
    /// `nil` means no container with this id exists yet ("not created").
    let state: ContainerState?
}
