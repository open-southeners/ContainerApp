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
            .frame(minHeight: 220, idealHeight: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
