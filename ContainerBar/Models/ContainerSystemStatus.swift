enum ContainerSystemStatus: Equatable, Hashable, Sendable {
    case running
    case stopped
    case unavailable
    case unknown(String)

    var displayName: String {
        switch self {
        case .running:          return "Running"
        case .stopped:          return "Stopped"
        case .unavailable:      return "Unavailable"
        case .unknown(let msg): return msg.isEmpty ? "Unknown" : msg
        }
    }
}
