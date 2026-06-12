import SwiftUI

/// Overview tab: key-value rows for a selected container's metadata.
struct ContainerOverviewView: View {
    let container: ContainerSummary

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Form {
            LabeledContent("ID") {
                Text(container.id)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Name", value: container.name)
            LabeledContent("Image", value: container.image)
            LabeledContent("State", value: container.state.displayName)

            if let created = container.createdAt {
                LabeledContent("Created", value: Self.dateFormatter.string(from: created))
            } else {
                LabeledContent("Created", value: "–")
            }

            if let started = container.startedAt {
                LabeledContent("Started", value: Self.dateFormatter.string(from: started))
            } else {
                LabeledContent("Started", value: "–")
            }

            LabeledContent("Ports", value: container.ports ?? "–")
            LabeledContent("Command", value: container.command ?? "–")
        }
        .formStyle(.grouped)
    }
}
