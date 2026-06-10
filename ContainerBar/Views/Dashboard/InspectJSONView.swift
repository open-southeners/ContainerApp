import SwiftUI
import AppKit

/// Inspect tab: raw JSON/text in a monospaced scroll view with Refresh and Copy actions.
struct InspectJSONView: View {
    @Environment(ContainersViewModel.self) private var model
    let container: ContainerSummary

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack {
                Button {
                    Task { await model.inspect(container) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.inspectText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(model.inspectText.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if model.inspectText.isEmpty {
                EmptyStateView(
                    title: "No Inspect Data",
                    systemImage: "curlybraces",
                    description: "Press Refresh to inspect this container."
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(model.inspectText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
    }
}
