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
                    description: "Press Refresh to load logs for this container."
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(model.logsText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
    }
}
