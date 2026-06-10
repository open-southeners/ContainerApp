import SwiftUI

/// Stats tab: CPU, memory, network, and block I/O from the live stats array.
struct StatsView: View {
    @Environment(ContainersViewModel.self) private var model
    let container: ContainerSummary

    private var containerStats: ContainerStats? {
        model.stats.first { $0.id == container.id }
    }

    var body: some View {
        if let stats = containerStats {
            Form {
                LabeledContent("CPU") {
                    if let cpu = stats.cpuPercent {
                        Text(String(format: "%.1f%%", cpu))
                    } else {
                        Text("–")
                    }
                }
                LabeledContent("Memory", value: stats.memoryText ?? "–")
                LabeledContent("Network I/O", value: stats.networkText ?? "–")
                LabeledContent("Block I/O", value: stats.blockIOText ?? "–")
            }
            .formStyle(.grouped)
        } else {
            EmptyStateView(
                title: "No Stats",
                systemImage: "chart.bar",
                description: "No statistics are available for this container."
            )
        }
    }
}
