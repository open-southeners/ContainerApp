import SwiftUI

/// Sidebar listing all `SidebarSection` cases with their SF Symbol icons.
struct SidebarView: View {
    @Environment(ContainersViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(SidebarSection.allCases, id: \.self, selection: $model.sidebarSelection) { section in
            Label(section.displayName, systemImage: section.systemImage)
        }
        .listStyle(.sidebar)
        .navigationTitle("Containers")
    }
}
