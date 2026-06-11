import Foundation

/// A UI-ready summary of a locally-available container image,
/// derived from one element of `container image list --format json`.
struct ImageSummary: Identifiable, Hashable, Sendable {
    /// SHA-256 hex digest of the image index manifest (no `sha256:` prefix).
    /// Stable table identity across refreshes.
    let id: String

    /// Fully-qualified reference as returned by the CLI, e.g.
    /// `docker.io/library/alpine:latest`. Used for in-use cross-referencing
    /// against `ContainerSummary.imageReference`.
    let reference: String

    /// Human-readable image name: `docker.io/library/` prefix stripped,
    /// tag removed. E.g. `"alpine"` for `docker.io/library/alpine:latest`.
    let displayName: String

    /// Tag component of the reference, e.g. `"latest"`. `nil` when the
    /// reference contains no tag (digest-only or name-only refs).
    let tag: String?

    /// First 12 hex characters of `id` — shown in the UI where digest space is tight.
    let digestShort: String

    /// Parsed `configuration.creationDate`, or `nil` when absent or unparseable.
    let createdAt: Date?

    /// Sum of `variants[].size` in bytes — the real on-disk image weight.
    /// `nil` when the element has no `variants` array.
    ///
    /// - Important: `configuration.descriptor.size` is the manifest index size
    ///   (~9 KB); do **not** use that field for storage reporting.
    let sizeBytes: Int64?

    /// Architecture strings from each variant's `platform.architecture`,
    /// e.g. `["arm64"]`. May contain `"unknown"` for attestation shims.
    let architectures: [String]

    /// `true` when the view model has cross-referenced this image against the
    /// active container list. Never decoded from the CLI; set by the view model.
    var isInUse: Bool = false
}
