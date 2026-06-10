import SwiftUI

// MARK: - App entry point

@main
struct ContainerBarApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            Image(systemName: "shippingbox")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Containers", id: "containers-window") {
            ContainersDashboardView()
        }
        .defaultSize(width: 1100, height: 720)
    }
}

// MARK: - Menu-bar popover (placeholder)

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers")
                .font(.headline)

            Text("No containers running yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Show More\u{2026}") {
                openWindow(id: "containers-window")
            }
            .buttonStyle(.plain)

            Button("Quit ContainerBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Dashboard placeholder

struct ContainersDashboardView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Containers Dashboard")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Container list and management will appear here in a future phase.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
