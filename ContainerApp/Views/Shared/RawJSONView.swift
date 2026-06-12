import SwiftUI
import AppKit

/// Monospaced, selectable raw-text pane with a Refresh + Copy toolbar row and
/// an empty state. The caller owns the text and the refresh side effect.
struct RawJSONView: View {
    /// The text to display. When empty the empty-state placeholder is shown instead.
    let text: String
    /// Title shown in the empty-state placeholder.
    var emptyTitle: String = "No Data"
    /// Description shown below the empty-state title.
    var emptyDescription: String = "Press Refresh to load."
    /// Called when the user taps Refresh.
    let onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(text.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if text.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    systemImage: "curlybraces",
                    description: emptyDescription
                )
            } else {
                SelectableMonospacedTextView(text: text)
            }
        }
    }
}
