import SwiftUI

// MARK: - App entry point

@main
struct ContainerBarApp: App {
    @State private var model = ContainersViewModel(runtime: MockContainerRuntime())

    var body: some Scene {
        MenuBarExtra {
            MenuBarContainerView()
                .environment(model)
        } label: {
            Image(systemName: "shippingbox")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Containers", id: "containers-window") {
            ContainersDashboardView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
