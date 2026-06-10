import SwiftUI

/// Main content area for the dashboard.
/// Switches on sidebar selection: Images/Settings show a placeholder;
/// all other sections show the container table + optional detail panel.
struct ContainerContentView: View {
    @Environment(ContainersViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        switch model.sidebarSelection {
        case .images:
            EmptyStateView(
                title: "Images",
                systemImage: "externaldrive",
                description: "Image management is coming soon."
            )
        case .settings:
            EmptyStateView(
                title: "Settings",
                systemImage: "gear",
                description: "Settings are coming soon."
            )
        default:
            // System-status states take precedence over the container table.
            if model.systemStatus == .unavailable {
                cliNotFoundContent
            } else if model.systemStatus == .stopped {
                systemStoppedContent(model: model)
            } else {
                containerListContent(model: model)
            }
        }
    }

    // MARK: System-status full-area states

    private var cliNotFoundContent: some View {
        ContentUnavailableView {
            Label("Apple container CLI not found", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Install Apple container, then configure the path in Settings.")
        }
    }

    @ViewBuilder
    private func systemStoppedContent(model: ContainersViewModel) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Container system is not running", systemImage: "power")
            } description: {
                Text("Start the container system to list and manage containers.")
            } actions: {
                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                } else {
                    Button("Start System") {
                        Task { await model.startSystem() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
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
                        TableColumn("Name") { container in
                            Text(container.name)
                                .fontWeight(.medium)
                        }
                        .width(min: 120, ideal: 160)

                        TableColumn("Image") { container in
                            Text(container.image)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 140, ideal: 200)

                        TableColumn("State") { container in
                            Label(container.state.displayName, systemImage: container.state.systemImage)
                                .foregroundStyle(stateColor(container.state))
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
    }

    // MARK: Helpers

    private func emptyDescription(for section: SidebarSection?) -> String {
        switch section {
        case .running:  return "No containers are currently running."
        case .stopped:  return "No stopped containers found."
        default:        return "No containers are available. Start the system and run a container."
        }
    }

    private func stateColor(_ state: ContainerState) -> Color {
        switch state {
        case .running:  return .green
        case .stopped:  return .secondary
        case .created:  return .blue
        case .exited:   return .orange
        case .unknown:  return .gray
        }
    }
}
