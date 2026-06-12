import SwiftUI

extension ContainerState {
    /// The tint color used by views to represent this state.
    var color: Color {
        switch self {
        case .running:  return .green
        case .stopped:  return .secondary
        case .created:  return .blue
        case .exited:   return .orange
        case .unknown:  return .gray
        }
    }
}
