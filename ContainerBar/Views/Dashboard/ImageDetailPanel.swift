import SwiftUI

// MARK: - Tab enum

/// Tabs available in the image detail panel.
private enum ImageDetailTab: String, CaseIterable, Hashable {
    case overview
    case rawJSON

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .rawJSON:  return "Raw JSON"
        }
    }
}

// MARK: - Panel

/// Detail panel shown below the image table for the selected image.
/// Header: display name, tag badge, and digest.
/// Body: segmented picker over `ImageDetailTab` + matching tab view.
struct ImageDetailPanel: View {
    @Environment(ContainersViewModel.self) private var model
    let image: ImageSummary

    @State private var selectedTab: ImageDetailTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack(alignment: .center, spacing: 12) {
                // Name + full reference
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.displayName)
                        .font(.headline)
                    Text(image.reference)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Tag badge
                if let tag = image.tag {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(.blue.opacity(0.4), lineWidth: 1))
                }

                Spacer()

                // In-use badge
                if image.isInUse {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(.green.opacity(0.35), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // MARK: Tab Picker
            Picker("Detail Tab", selection: $selectedTab) {
                ForEach(ImageDetailTab.allCases, id: \.self) { tab in
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
                switch selectedTab {
                case .overview:
                    ImageOverviewView(image: image)
                case .rawJSON:
                    RawJSONView(
                        text: model.imageInspectText,
                        emptyTitle: "No Inspect Data",
                        emptyDescription: "Press Refresh to inspect this image."
                    ) {
                        await model.inspectImage(image)
                    }
                    .task(id: image.id) {
                        await model.inspectImage(image)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Overview tab

/// Overview tab: key-value rows for a selected image's metadata.
private struct ImageOverviewView: View {
    @Environment(ContainersViewModel.self) private var model
    let image: ImageSummary

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    var body: some View {
        Form {
            LabeledContent("Reference") {
                Text(image.reference)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            LabeledContent("Digest") {
                Text(image.digestShort)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            if let created = image.createdAt {
                LabeledContent("Created", value: Self.dateFormatter.string(from: created))
            } else {
                LabeledContent("Created", value: "–")
            }

            if let bytes = image.sizeBytes {
                LabeledContent("Size", value: Self.byteFormatter.string(fromByteCount: bytes))
            } else {
                LabeledContent("Size", value: "–")
            }

            let arches = image.architectures.filter { $0 != "unknown" }
            if arches.isEmpty {
                LabeledContent("Architectures", value: "–")
            } else {
                LabeledContent("Architectures", value: arches.joined(separator: ", "))
            }

            if image.isInUse {
                let inUseNames = model.containers
                    .filter { $0.imageReference == image.reference }
                    .map(\.name)
                if !inUseNames.isEmpty {
                    LabeledContent("In Use By", value: inUseNames.joined(separator: ", "))
                }
            }
        }
        .formStyle(.grouped)
    }
}
