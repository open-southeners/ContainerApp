import SwiftUI

/// Detail panel shown below the container table for the selected container.
/// Header: name, image, state badge, and quick-action buttons.
/// Body: segmented picker over `ContainerDetailTab` + matching tab view.
struct ContainerDetailPanel: View {
    @Environment(ContainersViewModel.self) private var model
    let container: ContainerSummary

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // MARK: Header
            HStack(alignment: .center, spacing: 12) {
                // Name + Image
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.headline)
                    Text(container.image)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // State badge
                Label(container.state.displayName, systemImage: container.state.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(container.state.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(container.state.color.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(container.state.color.opacity(0.4), lineWidth: 1))

                Spacer()

                // Action buttons
                Button {
                    model.detailTab = .logs
                    Task { await model.loadLogs(container) }
                } label: {
                    Label("Logs", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)

                Button {
                    model.openShell(container)
                } label: {
                    Label("Shell", systemImage: "terminal")
                }
                .buttonStyle(.borderless)

                Button {
                    model.detailTab = .inspect
                    Task { await model.inspect(container) }
                } label: {
                    Label("Inspect", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)

                Divider()
                    .frame(height: 20)

                Button(role: .destructive) {
                    Task { await model.stop(container) }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.borderless)
                .tint(.orange)

                Button(role: .destructive) {
                    Task { await model.kill(container) }
                } label: {
                    Label("Kill", systemImage: "bolt.circle")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    Task { await model.delete(container) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // MARK: Tab Picker
            Picker("Detail Tab", selection: $model.detailTab) {
                ForEach(ContainerDetailTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // MARK: Tab Content
            Group {
                switch model.detailTab {
                case .overview:
                    ContainerOverviewView(container: container)
                case .logs:
                    LogsView(container: container)
                case .inspect:
                    InspectJSONView(container: container)
                case .stats:
                    StatsView(container: container)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}
