import SwiftUI

/// Root dashboard window: `NavigationSplitView` with sidebar + content + toolbar actions.
struct ContainersDashboardView: View {
    @Environment(ContainersViewModel.self) private var model

    @State private var isShowingPruneConfirmation = false

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
                    isShowingPruneConfirmation = true
                } label: {
                    Label("Prune", systemImage: "trash.slash")
                }
            }
        }
        .confirmationDialog("Remove all stopped containers?", isPresented: $isShowingPruneConfirmation) {
            Button("Prune", role: .destructive) {
                Task { await model.prune() }
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
