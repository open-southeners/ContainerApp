import SwiftUI

/// Root dashboard window: `NavigationSplitView` with sidebar + content + toolbar actions.
struct ContainersDashboardView: View {
    @Environment(ContainersViewModel.self) private var model

    @State private var isShowingPruneConfirmation = false

    /// `true` when the sidebar is showing the Images section.
    private var isImagesSection: Bool {
        model.sidebarSelection == .images
    }

    /// `true` when the sidebar is showing the Compose section.
    /// The Prune toolbar button is hidden for Compose — there is no compose-level
    /// prune operation; removal is handled per-project inside `ComposeProjectsView`.
    private var isComposeSection: Bool {
        model.sidebarSelection == .compose
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } detail: {
            ContainerContentView()
        }
        .toolbar {
            // Navigation / leading actions
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    Task { await model.startSystem() }
                } label: {
                    Label("Start System", systemImage: "play.fill")
                }
                .disabled(model.systemStatus == .running)

                Button {
                    Task { await model.stopSystem() }
                } label: {
                    Label("Stop System", systemImage: "stop.fill")
                }
                .disabled(model.systemStatus != .running)
            }

            // Primary / trailing actions
            ToolbarItemGroup(placement: .primaryAction) {
                // Phase-4 placeholder — always disabled
                Button {
                    // TODO: Phase 4 — implement Run Container
                } label: {
                    Label("Run Container", systemImage: "play.circle.fill")
                }
                .disabled(true)

                // The Prune button label and confirmation text adapt to the active section:
                // Images section → prune dangling images; all other sections → prune stopped containers.
                // Hidden for the Compose section — no compose-level prune operation exists;
                // project removal is handled inside ComposeProjectsView.
                if !isComposeSection {
                    Button {
                        isShowingPruneConfirmation = true
                    } label: {
                        Label(
                            isImagesSection ? "Prune Images" : "Prune",
                            systemImage: "trash.slash"
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            isImagesSection ? "Remove dangling images?" : "Remove all stopped containers?",
            isPresented: $isShowingPruneConfirmation
        ) {
            if isImagesSection {
                Button("Prune Images", role: .destructive) {
                    Task { await model.pruneImages() }
                }
            } else {
                Button("Prune", role: .destructive) {
                    Task { await model.prune() }
                }
            }
        }
        .task {
            // Initial full refresh (shows isLoading indicator)
            await model.refresh()
            // Poll every 5 s with quiet refreshes; task is cancelled when the window closes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await model.refresh(quiet: true)
            }
        }
    }
}
