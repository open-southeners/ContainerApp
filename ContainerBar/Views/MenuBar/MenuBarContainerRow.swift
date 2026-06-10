import SwiftUI

/// A single row in the menu-bar popover representing one container.
/// Shows the container's state icon, name, image, and quick-action buttons.
struct MenuBarContainerRow: View {
    @Environment(ContainersViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    let container: ContainerSummary

    var body: some View {
        HStack(spacing: 8) {
            // State icon
            Image(systemName: container.state.systemImage)
                .foregroundStyle(container.state.color)
                .frame(width: 16)

            // Name + image
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quick-action buttons
            HStack(spacing: 4) {
                Button {
                    model.select(container)
                    model.detailTab = .logs
                    openWindow(id: "containers-window")
                    Task {
                        await model.loadLogs(container)
                    }
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Show Logs")

                Button {
                    model.openShell(container)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("Open Shell")

                Button(role: .destructive) {
                    Task {
                        await model.stop(container)
                    }
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop Container")
                .foregroundStyle(.red)
                .disabled(container.state != .running)
            }
        }
        .padding(.vertical, 2)
    }
}
