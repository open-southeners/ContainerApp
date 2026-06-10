struct ContainerStats: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String?
    var cpuPercent: Double?
    var cpuUsageUsec: Int64?
    var memoryUsageBytes: UInt64?
    var memoryLimitBytes: UInt64?
    var memoryText: String?
    var networkText: String?
    var blockIOText: String?
}
