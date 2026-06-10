import SwiftUI

/// Thin wrapper around `ContentUnavailableView` so all empty states look consistent.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
    }
}
