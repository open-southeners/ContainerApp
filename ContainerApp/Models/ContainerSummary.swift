import Foundation

struct ContainerSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var image: String
    var state: ContainerState
    var status: String?
    var command: String?
    var createdAt: Date?
    var startedAt: Date?
    var ports: String?
    var cpuText: String?
    var memoryText: String?
    /// Raw fully-qualified image reference as reported by the CLI, e.g.
    /// `docker.io/library/alpine:latest`. Used for in-use cross-referencing
    /// with `ImageSummary.reference`. `nil` when the container has no image
    /// reference in its configuration. Unlike `image`, this field is **not**
    /// stripped of the `docker.io/library/` prefix.
    var imageReference: String? = nil
}
