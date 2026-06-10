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
}
