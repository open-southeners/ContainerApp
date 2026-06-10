import SwiftUI

/// The content view displayed inside the MenuBarExtra popover.
/// Shows a title, system status, up to 5 running containers, and footer controls.
struct MenuBarContainerView: View {
    @Environment(ContainersViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Containers")
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: systemStatusImage)
                        .foregroundStyle(systemStatusColor)
                        .imageScale(.small)
                    Text("System: \(model.systemStatus.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // MARK: Error message (if any)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
            }

            // MARK: Container rows (or system-status replacement)
            if model.systemStatus == .unavailable {
                Text("Apple container CLI not found. Install Apple container, then configure the path in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.systemStatus == .stopped {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Container system is not running.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if model.isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                            Text("Starting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Start System") {
                            Task { await model.startSystem() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isLoading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else if model.runningContainers.isEmpty {
                Text("No containers running.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.runningContainers.prefix(5))) { container in
                        MenuBarContainerRow(container: container)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // MARK: Footer controls
            VStack(alignment: .leading, spacing: 2) {
                // Refresh
                Button {
                    Task {
                        await model.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                // Start / Stop system depending on current status
                if model.systemStatus == .running {
                    Button {
                        Task {
                            await model.stopSystem()
                        }
                    } label: {
                        Label("Stop System", systemImage: "stop.fill")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task {
                            await model.startSystem()
                        }
                    } label: {
                        Label("Start System", systemImage: "play.fill")
                    }
                    .buttonStyle(.plain)
                }

                // Show More button — opens the full dashboard window
                Button {
                    openWindow(id: "containers-window")
                } label: {
                    Label("Show More\u{2026}", systemImage: "rectangle.expand.diagonal")
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 2)

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit ContainerBar", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .task {
            await model.refresh()
        }
    }

    // MARK: - Helpers

    private var systemStatusImage: String {
        switch model.systemStatus {
        case .running:     return "checkmark.circle.fill"
        case .stopped:     return "stop.circle.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        case .unknown:     return "questionmark.circle.fill"
        }
    }

    private var systemStatusColor: Color {
        switch model.systemStatus {
        case .running:     return .green
        case .stopped:     return .orange
        case .unavailable: return .red
        case .unknown:     return .secondary
        }
    }
}
