import SwiftUI
import AppKit

/// Settings pane shown when the user selects "Settings" in the sidebar.
///
/// Provides a text field (and Browse… button) for overriding the path to the
/// `container` CLI binary.  The value is persisted via `@AppStorage` so it is
/// available to `ContainerCLIRuntime` on every subsequent resolve cycle.
struct SettingsView: View {

    // MARK: Stored state

    @AppStorage("containerCLIPath") private var cliPath: String = ""

    // MARK: Derived validation state

    /// Three mutually exclusive states for the inline validation row.
    private enum ValidationState {
        case empty          // Field is blank → using default discovery
        case found          // Non-empty path and FileManager says it is executable
        case notFound       // Non-empty path but missing / not executable
    }

    private var validationState: ValidationState {
        let trimmed = cliPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        return FileManager.default.isExecutableFile(atPath: trimmed) ? .found : .notFound
    }

    // MARK: Body

    var body: some View {
        Form {
            Section {
                // Path text field
                TextField("/usr/local/bin/container", text: $cliPath)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)

                // Browse… button
                Button("Browse…") { presentOpenPanel() }

                // Inline validation feedback
                validationRow
            } header: {
                Text("Container CLI")
            } footer: {
                Text("Changes take effect on the next refresh.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    // MARK: Validation row

    @ViewBuilder
    private var validationRow: some View {
        switch validationState {
        case .empty:
            Label {
                Text("Using default discovery (/usr/local/bin, /opt/homebrew/bin, PATH).")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

        case .found:
            Label {
                Text("CLI found.")
                    .foregroundStyle(.green)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.footnote)

        case .notFound:
            Label {
                Text("Not found or not executable — falling back to default discovery.")
                    .foregroundStyle(.orange)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.footnote)
        }
    }

    // MARK: Browse panel

    /// Presents an `NSOpenPanel` restricted to a single executable file and
    /// writes the chosen path back into the `@AppStorage` binding.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select container CLI"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        cliPath = url.path
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(width: 500, height: 400)
}
