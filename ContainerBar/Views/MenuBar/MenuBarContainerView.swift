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
                        .menuRowLabel()
                }
                .buttonStyle(.plain)
                .menuRowHover()

                // Start / Stop system depending on current status.
                // The "Start System" button is suppressed here when the system
                // is stopped, because the stopped-state panel above already
                // shows its own prominent Start System button.
                if model.systemStatus == .running {
                    Button {
                        Task {
                            await model.stopSystem()
                        }
                    } label: {
                        Label("Stop System", systemImage: "stop.fill")
                            .menuRowLabel()
                    }
                    .buttonStyle(.plain)
                    .menuRowHover()
                } else if model.systemStatus != .stopped {
                    Button {
                        Task {
                            await model.startSystem()
                        }
                    } label: {
                        Label("Start System", systemImage: "play.fill")
                            .menuRowLabel()
                    }
                    .buttonStyle(.plain)
                    .menuRowHover()
                }

                // Show More button — opens the full dashboard window, focusing it if already open
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "containers-window")
                } label: {
                    Label("Show More\u{2026}", systemImage: "rectangle.expand.diagonal")
                        .menuRowLabel()
                }
                .buttonStyle(.plain)
                .menuRowHover()

                Divider()
                    .padding(.vertical, 4)

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit ContainerBar", systemImage: "power")
                        .menuRowLabel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .menuRowHover()
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

// MARK: - Footer row styling

private extension View {
    /// Standard styling for a footer menu row: roomier icon/text spacing,
    /// a full-width hit target, and vertical padding so rows aren't cramped.
    func menuRowLabel() -> some View {
        self
            .labelStyle(MenuRowLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
    }

    /// Adds a menu-style hover highlight background to a footer button.
    func menuRowHover() -> some View {
        modifier(MenuRowHoverModifier())
    }
}

/// Provides a rounded highlight on hover using the system menu-item selection color,
/// matching the appearance of native macOS top-bar menu rows.
private struct MenuRowHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.2) : Color.clear)
                    .padding(.horizontal, -4)
            )
            .onHover { isHovered = $0 }
    }
}

/// Label style that gives footer rows consistent icon width and spacing.
private struct MenuRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 16, alignment: .center)
            configuration.title
        }
    }
}
