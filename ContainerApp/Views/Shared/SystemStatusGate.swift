import SwiftUI

/// Wraps any section that requires the container core to be running.
/// Shows a full-area CLI-not-found or system-stopped state (with the Start
/// System action) when the core is unavailable; renders `content` otherwise.
struct SystemStatusGate<Content: View>: View {
    @Environment(ContainersViewModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch model.systemStatus {
        case .unavailable:
            cliNotFoundContent
        case .stopped:
            systemStoppedContent
        default:
            content()
        }
    }

    // MARK: Full-area system-status states

    private var cliNotFoundContent: some View {
        ContentUnavailableView {
            Label("Apple container CLI not found", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Install Apple container, then configure the path in Settings.")
        }
    }

    @ViewBuilder
    private var systemStoppedContent: some View {
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
}
