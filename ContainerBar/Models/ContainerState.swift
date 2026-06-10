enum ContainerState: String, Codable, Hashable, Sendable {
    case running
    case stopped
    case created
    case exited
    case unknown

    var displayName: String {
        switch self {
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .created:  return "Created"
        case .exited:   return "Exited"
        case .unknown:  return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .running:  return "play.circle.fill"
        case .stopped:  return "stop.circle"
        case .created:  return "circle"
        case .exited:   return "xmark.circle"
        case .unknown:  return "questionmark.circle"
        }
    }
}
