import SwiftUI

/// Root dashboard window: `NavigationSplitView` with sidebar + content + toolbar actions.
struct ContainersDashboardView: View {
    @Environment(ContainersViewModel.self) private var model

    @State private var showPruneAlert = false

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

                Button {
                    showPruneAlert = true
                } label: {
                    Label("Prune", systemImage: "trash.slash")
                }
            }
        }
        .alert("Prune", isPresented: $showPruneAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            // TODO: Phase 3 — implement Prune (remove stopped containers + dangling images)
            Text("Prune is not yet implemented. It will be available in Phase 3.")
        }
        .task {
            await model.refresh()
        }
    }
}
