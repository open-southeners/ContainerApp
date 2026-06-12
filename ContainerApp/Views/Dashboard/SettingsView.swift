import SwiftUI
import AppKit

/// Settings pane shown when the user selects "Settings" in the sidebar.
///
/// Provides text fields (and Browse… buttons) for overriding the paths to the
/// `container` and `container-compose` CLI binaries.  Values are persisted via
/// `@AppStorage` so they are available to the respective runtimes on every
/// subsequent resolve cycle.
struct SettingsView: View {
    @Environment(ContainersViewModel.self) private var model

    var body: some View {
        Form {
            CLIPathOverrideSection(
                title: "Container CLI",
                placeholder: "/usr/local/bin/container",
                storageKey: "containerCLIPath",
                footer: "Changes take effect on the next refresh."
            )

            CLIPathOverrideSection(
                title: "Container-Compose CLI",
                placeholder: "/opt/homebrew/bin/container-compose",
                storageKey: "containerComposeCLIPath",
                footer: "Install with: brew install container-compose. Changes take effect on the next refresh.",
                onPathChanged: {
                    // Reset the availability probe so the next refresh re-checks the binary.
                    Task { await model.reprobeCompose() }
                }
            )
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

// MARK: - Reusable path-override section

/// A `Section` containing a path text field, a Browse… button, and inline
/// validation feedback.  Parameterised so it can be reused for different CLI
/// binaries without copy-pasting.
///
/// `@AppStorage` requires a constant key literal, so the key is passed as a
/// `let` constant and the `AppStorage` wrapper is constructed via the
/// `init(wrappedValue:_:store:)` initialiser inside the view.
private struct CLIPathOverrideSection: View {

    // MARK: Parameters

    let title: String
    let placeholder: String
    let storageKey: String
    let footer: String
    /// Optional closure called when the user commits an edited path — on Return
    /// (`.onSubmit`), when focus leaves the field, or when a Browse… panel
    /// selection is confirmed.  Not called on every character typed, so callers
    /// can perform expensive work (e.g. re-probing a binary) without debouncing.
    /// Inline validation still updates live because it derives from `path` directly.
    var onPathChanged: (() -> Void)? = nil

    // MARK: Local state — backed by @AppStorage via the forwarded binding below

    @State private var path: String = ""
    @FocusState private var isFocused: Bool

    // MARK: Derived validation state

    /// Three mutually exclusive states for the inline validation row.
    private enum ValidationState {
        case empty          // Field is blank → using default discovery
        case found          // Non-empty path and FileManager says it is executable
        case notFound       // Non-empty path but missing / not executable
    }

    private var validationState: ValidationState {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        return FileManager.default.isExecutableFile(atPath: trimmed) ? .found : .notFound
    }

    // MARK: Body

    var body: some View {
        // Sync @State with @AppStorage on appearance and use onChange to propagate edits.
        Section {
            // Path text field
            TextField(placeholder, text: $path)
                .font(.system(.body, design: .monospaced))
                .disableAutocorrection(true)
                .focused($isFocused)
                .onChange(of: path) {
                    // Persist to UserDefaults on every keystroke so inline
                    // validation (validationState) always reflects the current text.
                    UserDefaults.standard.set(path, forKey: storageKey)
                    // NOTE: onPathChanged is NOT called here to avoid a full
                    // reprobeCompose() on every character typed.
                }
                .onSubmit {
                    // Commit on Return key.
                    onPathChanged?()
                }
                .onChange(of: isFocused) {
                    // Commit when focus leaves the field.
                    if !isFocused {
                        onPathChanged?()
                    }
                }

            // Browse… button
            Button("Browse…") { presentOpenPanel() }

            // Inline validation feedback
            validationRow
        } header: {
            Text(title)
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            // Bootstrap @State from UserDefaults so the field isn't blank on first render.
            path = UserDefaults.standard.string(forKey: storageKey) ?? ""
        }
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
    /// writes the chosen path back into the local state (which syncs to UserDefaults).
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select \(title)"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        // A panel selection is a committed value; fire the callback immediately.
        onPathChanged?()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(ContainersViewModel(runtime: MockContainerRuntime()))
        .frame(width: 500, height: 500)
}
