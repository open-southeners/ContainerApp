import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Compose section of the dashboard.
/// Shown inside a `SystemStatusGate` so the container core must be running
/// before this view appears.  Mirrors the structure of `ImagesView`.
struct ComposeProjectsView: View {
    @Environment(ContainersViewModel.self) private var model

    /// The project currently pending a remove confirmation.
    @State private var projectToRemove: ComposeProject?

    var body: some View {
        @Bindable var model = model

        // When composeAvailable is nil, a probe is still in flight — show a spinner.
        if model.composeAvailable == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.composeAvailable == false {
            // Compose binary is missing — show the install prompt.
            composeNotInstalledContent
        } else {
            composeProjectsContent(model: model)
        }
    }

    // MARK: Compose not installed state

    private var composeNotInstalledContent: some View {
        @Bindable var model = model
        return VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Container-Compose Is Not Installed", systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("Install container-compose with Homebrew, or configure a custom path in Settings.")
            } actions: {
                VStack(spacing: 12) {
                    // Brew install command in selectable monospace with a Copy button.
                    HStack(spacing: 8) {
                        Text("brew install container-compose")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                "brew install container-compose",
                                forType: .string
                            )
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        // Settings deep-link hint.
                        Button("Open Settings") {
                            model.sidebarSelection = .settings
                        }
                        .buttonStyle(.bordered)

                        // Retry button: re-probe the compose binary.
                        Button("Retry") {
                            Task { await model.reprobeCompose() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: Projects list content

    @ViewBuilder
    private func composeProjectsContent(model: ContainersViewModel) -> some View {
        @Bindable var model = model
        // GeometryReader forces VSplitView to fill the offered width — same pattern
        // as ImagesView and containerListContent.
        GeometryReader { geometry in
        VSplitView {
            // MARK: Top pane — error banner + table
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBannerView(message: message) {
                        model.errorMessage = nil
                    }
                }

                if model.composeProjects.isEmpty {
                    EmptyStateView(
                        title: "No Compose Projects",
                        systemImage: "square.stack.3d.up",
                        description: "Add a docker-compose.yml to get started."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Footer button — always visible even when the list is empty.
                    .safeAreaInset(edge: .bottom) {
                        addProjectButton
                    }
                } else {
                    Table(model.composeProjects, selection: $model.selectedComposeProjectID) {
                        // Status: aggregate dot/icon for the project.
                        TableColumn("Status") { project in
                            projectStatusView(project)
                        }
                        .width(min: 50, ideal: 60)

                        // Name: flexible, absorbs remaining horizontal space.
                        TableColumn("Name") { project in
                            Text(project.displayName)
                                .fontWeight(.medium)
                        }

                        // Services: "N of M running" summary.
                        TableColumn("Services") { project in
                            Text(servicesSummary(project))
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 100, ideal: 130)

                        // Path: abbreviated, full path on tooltip.
                        TableColumn("Path") { project in
                            Text(project.fileURL.abbreviatingWithTilde)
                                .foregroundStyle(.secondary)
                                .help(project.fileURL.path)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu(forSelectionType: String.self) { ids in
                        if let id = ids.first,
                           let project = model.composeProjects.first(where: { $0.id == id }) {
                            let isBusy = model.busyComposeProjects.contains(project.id)
                            let isMissing = project.isMissing

                            Button("Up") {
                                model.upProject(project)
                            }
                            .disabled(isBusy || isMissing)

                            Button("Down") {
                                model.downProject(project)
                            }
                            .disabled(isBusy || isMissing)

                            Button("Build") {
                                model.buildProject(project)
                            }
                            .disabled(isBusy || isMissing)

                            Divider()

                            Button("Remove from List…", role: .destructive) {
                                projectToRemove = project
                            }
                        }
                    } primaryAction: { ids in
                        if let id = ids.first {
                            model.selectedComposeProjectID = id
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        addProjectButton
                    }
                }
            }

            // MARK: Bottom pane — detail panel or hint
            Group {
                if let selected = model.selectedComposeProject {
                    ComposeProjectDetailPanel(project: selected)
                } else {
                    ContentUnavailableView(
                        "No Project Selected",
                        systemImage: "square.stack.3d.up.fill",
                        description: Text("Select a compose project from the list above to view its details.")
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, idealHeight: 280)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        } // GeometryReader
        .confirmationDialog(removeDialogTitle, isPresented: isShowingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove from List", role: .destructive) {
                if let project = projectToRemove {
                    model.removeComposeProject(project)
                }
                projectToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                projectToRemove = nil
            }
        } message: {
            Text("Removes the project from this list only. Containers and files are not touched.")
        }
    }

    // MARK: Add Project button

    private var addProjectButton: some View {
        HStack {
            Button {
                presentAddProjectPanel()
            } label: {
                Label("Add Project…", systemImage: "plus")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Spacer()
        }
        .background(.bar)
    }

    // MARK: Row helpers

    @ViewBuilder
    private func projectStatusView(_ project: ComposeProject) -> some View {
        if project.isMissing {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("File missing")
        } else {
            let statuses = ContainersViewModel.serviceStatuses(
                for: project,
                containers: model.containers
            )
            let runningCount = statuses.filter { $0.state == .running }.count
            let totalCount = statuses.count

            if totalCount == 0 {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("No services")
            } else if runningCount == totalCount {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("All running")
            } else if runningCount > 0 {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Some running")
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("None running")
            }
        }
    }

    private func servicesSummary(_ project: ComposeProject) -> String {
        if project.isMissing { return "–" }
        let statuses = ContainersViewModel.serviceStatuses(
            for: project,
            containers: model.containers
        )
        let total = statuses.count
        let running = statuses.filter { $0.state == .running }.count
        if total == 0 { return "No services" }
        return "\(running) of \(total) running"
    }

    // MARK: Confirmation dialog helpers

    private var isShowingRemoveConfirmation: Binding<Bool> {
        Binding(
            get: { projectToRemove != nil },
            set: { if !$0 { projectToRemove = nil } }
        )
    }

    private var removeDialogTitle: String {
        guard let project = projectToRemove else { return "Remove Project?" }
        return "Remove \"\(project.displayName)\"?"
    }

    // MARK: Add project panel

    /// Presents an `NSOpenPanel` for selecting a compose YAML file and registers it.
    private func presentAddProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select compose file"
        panel.prompt = "Add"

        // Allow YAML content types; fall back to allowing yaml/yml extensions.
        let yamlType = UTType(filenameExtension: "yaml") ?? .yaml
        let ymlType = UTType(filenameExtension: "yml") ?? .yaml
        panel.allowedContentTypes = [yamlType, ymlType]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addComposeProject(url: url)
    }
}

// MARK: - URL convenience

private extension URL {
    /// Returns the path with the home directory replaced by `~`, matching
    /// `NSString.abbreviatingWithTildeInPath` without the Foundation bridge overhead.
    var abbreviatingWithTilde: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = self.path
        guard p.hasPrefix(home) else { return p }
        return "~" + p.dropFirst(home.count)
    }
}

// MARK: - UTType fallback

private extension UTType {
    /// YAML UTType — available from macOS 14+; `public.yaml-content` as a fallback.
    static let yaml: UTType = UTType("public.yaml-content") ?? .plainText
}
