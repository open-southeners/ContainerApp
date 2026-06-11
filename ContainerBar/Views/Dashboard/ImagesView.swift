import SwiftUI

/// Images section of the dashboard.
/// Shown inside a `SystemStatusGate` so the container core must be running
/// before this view appears.  Mirrors the structure of `containerListContent`
/// in `ContainerContentView`.
struct ImagesView: View {
    @Environment(ContainersViewModel.self) private var model

    /// The image currently pending a delete confirmation.
    @State private var imageToDelete: ImageSummary?

    var body: some View {
        @Bindable var model = model
        VSplitView {
            // MARK: Top pane — banners + table
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBannerView(message: message) {
                        model.errorMessage = nil
                    }
                }

                // Informational prune-result banner (non-error, blue/accent tint).
                if let summary = model.pruneSummary {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            model.pruneSummary = nil
                        } label: {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss prune result")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.blue.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                if model.images.isEmpty {
                    EmptyStateView(
                        title: "No Images",
                        systemImage: "externaldrive",
                        description: "No container images are available locally."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(model.images, selection: $model.selectedImageID) {
                        // Name: no .width modifier → flexible, absorbs all remaining
                        // space after the fixed-width columns are measured.  This is
                        // what makes the table fill the pane horizontally; a column
                        // with no constraint is the only one the layout engine treats
                        // as truly resizable to fill the parent.
                        TableColumn("Name") { image in
                            Text(image.displayName)
                                .fontWeight(.medium)
                        }

                        TableColumn("Tag") { image in
                            Text(image.tag ?? "–")
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 80)

                        TableColumn("Size") { image in
                            Text(formattedSize(image.sizeBytes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .width(min: 70, ideal: 90)

                        // Created: also unconstrained so it can share any leftover
                        // horizontal space with Name, keeping date text readable.
                        TableColumn("Created") { image in
                            Text(formattedDate(image.createdAt))
                                .foregroundStyle(.secondary)
                        }

                        TableColumn("Arch") { image in
                            Text(filteredArchitectures(image.architectures).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 80)

                        TableColumn("In Use") { image in
                            if image.isInUse {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("In use")
                            } else {
                                Text("–")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Not in use")
                            }
                        }
                        .width(min: 50, ideal: 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu(forSelectionType: String.self) { ids in
                        if let id = ids.first, let image = model.images.first(where: { $0.id == id }) {
                            Button("Inspect") {
                                model.selectedImageID = image.id
                            }

                            Divider()

                            Button("Delete…", role: .destructive) {
                                imageToDelete = image
                            }
                        }
                    } primaryAction: { ids in
                        if let id = ids.first {
                            model.selectedImageID = id
                        }
                    }
                }
            }

            // MARK: Bottom pane — detail panel or hint
            Group {
                if let selected = model.selectedImage {
                    ImageDetailPanel(image: selected)
                } else {
                    ContentUnavailableView(
                        "No Image Selected",
                        systemImage: "externaldrive.fill",
                        description: Text("Select an image from the list above to view its details.")
                    )
                }
            }
            .frame(minHeight: 220, idealHeight: 280)
        }
        .confirmationDialog(deleteDialogTitle, isPresented: isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let image = imageToDelete {
                    Task { await model.deleteImage(image) }
                }
                imageToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                imageToDelete = nil
            }
        } message: {
            Text(deleteDialogMessage)
        }
    }

    // MARK: Confirmation dialog helpers

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { imageToDelete != nil },
            set: { if !$0 { imageToDelete = nil } }
        )
    }

    private var deleteDialogTitle: String {
        guard let image = imageToDelete else { return "Delete Image?" }
        return "Delete \"\(image.displayName)\"?"
    }

    private var deleteDialogMessage: String {
        guard let image = imageToDelete else { return "" }
        if image.isInUse {
            return "\(image.displayName) is used by a container. Deleting it may break that container."
        }
        return "This image will be permanently removed from local storage."
    }

    // MARK: Formatting helpers

    private func formattedSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "–" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.relative(presentation: .named))
    }

    /// Filters out `"unknown"` architecture entries that come from OCI attestation shims
    /// on multi-arch images, keeping only real platform identifiers.
    private func filteredArchitectures(_ architectures: [String]) -> [String] {
        architectures.filter { $0 != "unknown" }
    }
}
