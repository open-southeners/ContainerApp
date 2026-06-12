import SwiftUI

/// Detail panel shown below the compose project table for the selected project.
/// Header: display name, project name (when it differs), file path, and action buttons.
/// Body: services table + collapsible last-output section.
struct ComposeProjectDetailPanel: View {
    @Environment(ContainersViewModel.self) private var model
    let project: ComposeProject

    /// Whether the "Last Output" disclosure group is expanded.
    @State private var isOutputExpanded: Bool = true

    private var isBusy: Bool {
        model.busyComposeProjects.contains(project.id)
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // MARK: Header
            HStack(alignment: .center, spacing: 12) {
                // Display name + optional project name + file path
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.headline)
                    if project.projectName != project.displayName {
                        Text("Project: \(project.projectName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                Spacer()

                // Busy spinner — shown while any action is in flight for this project.
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }

                // Up button with rebuild variants in a menu.
                Menu {
                    Button("Up") {
                        model.upProject(project)
                    }
                    Button("Up (rebuild)") {
                        model.upProject(project, rebuild: true, noCache: false)
                    }
                    Button("Up (rebuild, no cache)") {
                        model.upProject(project, rebuild: true, noCache: true)
                    }
                } label: {
                    Label("Up", systemImage: "play.circle")
                } primaryAction: {
                    model.upProject(project)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderless)
                .disabled(isBusy || project.isMissing)

                Button {
                    model.downProject(project)
                } label: {
                    Label("Down", systemImage: "stop.circle")
                }
                .buttonStyle(.borderless)
                .tint(.orange)
                .disabled(isBusy || project.isMissing)

                Button {
                    model.buildProject(project)
                } label: {
                    Label("Build", systemImage: "hammer")
                }
                .buttonStyle(.borderless)
                .disabled(isBusy || project.isMissing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // MARK: Services table
            servicesTable(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: Last output
            if model.lastComposeOutput != nil {
                Divider()
                lastOutputSection(model: model)
            }
        }
    }

    // MARK: Services table

    @ViewBuilder
    private func servicesTable(model: ContainersViewModel) -> some View {
        @Bindable var model = model
        let statuses = ContainersViewModel.serviceStatuses(
            for: project,
            containers: model.containers
        )

        if statuses.isEmpty {
            ContentUnavailableView(
                "No Services",
                systemImage: "square.stack.3d.up",
                description: Text("This compose file declares no services.")
            )
        } else {
            // Use a List instead of Table for the services rows; the detail panel
            // typically has a small height, and a List with custom rows adapts better
            // to narrow/short layouts than a multi-column Table.
            List(statuses) { status in
                serviceRow(status, model: model)
                    .contextMenu {
                        Button("Up") {
                            model.upService(status.serviceName, in: project)
                        }
                        .disabled(isBusy)

                        Button("Down") {
                            model.downService(status.serviceName, in: project)
                        }
                        .disabled(isBusy)

                        // "Show Container" is only available when a matching container exists.
                        if let container = model.containers.first(where: { $0.id == status.id }) {
                            Divider()
                            Button("Show Container") {
                                model.sidebarSelection = .all
                                model.selectedContainerID = container.id
                            }
                        }
                    }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func serviceRow(_ status: ComposeServiceStatus, model: ContainersViewModel) -> some View {
        HStack(spacing: 10) {
            // State indicator
            stateIndicator(for: status.state)

            // Service name + container id
            VStack(alignment: .leading, spacing: 2) {
                Text(status.serviceName)
                    .fontWeight(.medium)
                Text(status.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            // Image ref (or dash when not present)
            if let image = status.image {
                Text(image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("–")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // State text
            stateLabel(for: status.state)
        }
    }

    @ViewBuilder
    private func stateIndicator(for state: ContainerState?) -> some View {
        if let state {
            Image(systemName: state.systemImage)
                .foregroundStyle(state.color)
                .frame(width: 16)
                .accessibilityLabel(state.displayName)
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityLabel("Not created")
        }
    }

    @ViewBuilder
    private func stateLabel(for state: ContainerState?) -> some View {
        if let state {
            Text(state.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(state.color.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(state.color.opacity(0.35), lineWidth: 1))
        } else {
            Text("not created")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: Last output section

    @ViewBuilder
    private func lastOutputSection(model: ContainersViewModel) -> some View {
        DisclosureGroup("Last Output", isExpanded: $isOutputExpanded) {
            SelectableMonospacedTextView(text: model.lastComposeOutput ?? "")
                .frame(minHeight: 80, maxHeight: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
