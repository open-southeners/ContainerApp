import SwiftUI

// MARK: - App entry point

@main
struct ContainerAppApp: App {
    @State private var model = ContainersViewModel(
        runtime: ContainerCLIRuntime(),
        composeRuntime: ContainerComposeCLIRuntime(),
        composeStore: ComposeProjectStore()
    )

    @MainActor
    private var menuBarIcon: Image {
        if let nsImage = NSImage(named: "TopBarIcon") {
            nsImage.isTemplate = true
            nsImage.size = NSSize(width: 18, height: 18)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "shippingbox")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContainerView()
                .environment(model)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

        Window("Containers", id: "containers-window") {
            ContainersDashboardView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
