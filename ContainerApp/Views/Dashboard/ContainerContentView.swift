import SwiftUI

/// Main content area for the dashboard.
/// Switches on sidebar selection: Images shows a placeholder (gated behind
/// `SystemStatusGate`); Settings renders `SettingsView`; all other sections
/// show the container table + optional detail panel, also gated.
struct ContainerContentView: View {
    @Environment(ContainersViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        switch model.sidebarSelection {
        case .images:
            SystemStatusGate {
                ImagesView()
            }
        case .settings:
            SettingsView()
        default:
            SystemStatusGate {
                containerListContent(model: model)
            }
        }
    }

    // MARK: Container list + detail panel

    @ViewBuilder
    private func containerListContent(model: ContainersViewModel) -> some View {
        @Bindable var model = model
        // GeometryReader is required here because VSplitView (NSSplitView-backed) sizes
        // itself to the measured fitting/ideal width of its pane content rather than
        // honouring an offered width.  Wrapping with `.frame(maxWidth: .infinity)` merely
        // centres the narrow split view; passing the explicit geometry size forces it to
        // actually fill the available space.  Do NOT replace with maxWidth: .infinity —
        // that regresses to the narrow layout when nothing is selected in the bottom pane.
        GeometryReader { geometry in
        VSplitView {
            // Top pane: error banner + table
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBannerView(message: message) {
                        model.errorMessage = nil
                    }
                }

                if model.filteredContainers.isEmpty {
                    EmptyStateView(
                        title: "No Containers",
                        systemImage: "shippingbox",
                        description: emptyDescription(for: model.sidebarSelection)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(model.filteredContainers, selection: $model.selectedContainerID) {
                        // Name: no .width modifier → flexible, absorbs remaining
                        // space after fixed-width columns are laid out.  This makes
                        // the table stretch to fill the pane horizontally.
                        TableColumn("Name") { container in
                            Text(container.name)
                                .fontWeight(.medium)
                        }

                        // Image: also unconstrained so it can grow with the window
                        // alongside Name, keeping long image references readable.
                        TableColumn("Image") { container in
                            Text(container.image)
                                .foregroundStyle(.secondary)
                        }

                        TableColumn("State") { container in
                            Label(container.state.displayName, systemImage: container.state.systemImage)
                                .foregroundStyle(container.state.color)
                                .labelStyle(.titleAndIcon)
                        }
                        .width(min: 100, ideal: 120)

                        TableColumn("CPU") { container in
                            Text(container.cpuText ?? "–")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .width(min: 60, ideal: 80)

                        TableColumn("Memory") { container in
                            Text(container.memoryText ?? "–")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .width(min: 80, ideal: 100)
                    }
                    .contextMenu(forSelectionType: ContainerSummary.ID.self) { ids in
                        if ids.count == 1,
                           let id = ids.first,
                           let container = model.filteredContainers.first(where: { $0.id == id }) {
                            let isRunning = container.state == .running

                            Button {
                                model.selectedContainerID = id
                                model.detailTab = .logs
                            } label: {
                                Label("Logs", systemImage: "doc.text")
                            }

                            Button {
                                model.openShell(container)
                            } label: {
                                Label("Shell", systemImage: "terminal")
                            }
                            .disabled(!isRunning)

                            Button {
                                model.selectedContainerID = id
                                model.detailTab = .inspect
                                Task { await model.inspect(container) }
                            } label: {
                                Label("Inspect", systemImage: "magnifyingglass")
                            }

                            Divider()

                            if isRunning {
                                Button(role: .destructive) {
                                    Task { await model.stop(container) }
                                } label: {
                                    Label("Stop", systemImage: "stop.circle")
                                }
                            } else {
                                Button {
                                    Task { await model.start(container) }
                                } label: {
                                    Label("Start", systemImage: "play.circle")
                                }
                            }

                            Button(role: .destructive) {
                                Task { await model.kill(container) }
                            } label: {
                                Label("Kill", systemImage: "bolt.circle")
                            }
                            .disabled(!isRunning)

                            Button(role: .destructive) {
                                Task { await model.delete(container) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } else if ids.count > 1 {
                            let containers = model.filteredContainers.filter { ids.contains($0.id) }
                            let anyRunning = containers.contains { $0.state == .running }

                            Button(role: .destructive) {
                                for container in containers where container.state == .running {
                                    Task { await model.kill(container) }
                                }
                            } label: {
                                Label("Kill Selected", systemImage: "bolt.circle")
                            }
                            .disabled(!anyRunning)

                            Button(role: .destructive) {
                                for container in containers {
                                    Task { await model.delete(container) }
                                }
                            } label: {
                                Label("Delete Selected", systemImage: "trash")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Bottom pane: detail panel or hint
            Group {
                if let selected = model.selectedContainer {
                    ContainerDetailPanel(container: selected)
                } else {
                    ContentUnavailableView(
                        "No Container Selected",
                        systemImage: "shippingbox.fill",
                        description: Text("Select a container from the list above to view its details.")
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, idealHeight: 280)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        } // GeometryReader
    }

    // MARK: Helpers

    private func emptyDescription(for section: SidebarSection?) -> String {
        switch section {
        case .running:  return "No containers are currently running."
        case .stopped:  return "No stopped containers found."
        default:        return "No containers are available. Start the system and run a container."
        }
    }
}
