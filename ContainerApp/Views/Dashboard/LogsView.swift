import SwiftUI
import AppKit

/// Logs tab: monospaced scrollable text with Refresh and Copy actions.
struct LogsView: View {
    @Environment(ContainersViewModel.self) private var model
    let container: ContainerSummary

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack {
                Button {
                    Task { await model.loadLogs(container) }
                } label: {
                    Label("Refresh Logs", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logsText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(model.logsText.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if model.logsText.isEmpty {
                EmptyStateView(
                    title: "No Logs",
                    systemImage: "doc.text",
                    description: "This container hasn't produced any log output."
                )
            } else {
                SelectableMonospacedTextView(text: model.logsText)
            }
        }
        // Load immediately, then keep polling while the tab is visible. Keyed on
        // the container id so switching containers cancels the old poll and loads
        // the new container's logs right away; leaving the tab cancels outright.
        .task(id: container.id) {
            await model.loadLogs(container)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await model.loadLogs(container, quiet: true)
            }
        }
    }
}
