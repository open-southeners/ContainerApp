import Foundation
import Yams

// MARK: - ComposeError

/// Errors thrown by `ComposeFileParser`.
enum ComposeError: Error, Sendable {
    /// The YAML could not be decoded or is structurally invalid.
    /// `message` contains a bounded preview of the raw content to aid debugging.
    case parseFailed(String)
}

// MARK: - Internal YAML decode types

/// Minimal compose-file skeleton — only the keys the app uses are decoded.
/// All fields are optional/lenient so unknown keys in the file don't break parsing
/// (same leniency policy as `CLIContainerDTO`).
private struct ComposeFileStub: Decodable {
    let name: String?
    /// Service values can be `null` (bare key) — hence the double-optional.
    let services: [String: ServiceStub?]?
}

/// Minimal per-service stub — only `image` is extracted for display.
private struct ServiceStub: Decodable {
    let image: String?
}

// MARK: - ComposeFileParser

/// Parses a docker-compose YAML file into a `ComposeProject`.
///
/// The parser is kept pure (no side effects other than throwing): `parse(text:fileURL:)`
/// is the testable core; `load(fileURL:)` is a thin wrapper that reads the file from disk.
enum ComposeFileParser {

    // MARK: Public API

    /// Parses compose YAML `text` as if it were located at `fileURL`.
    ///
    /// `fileURL` is used only for project-name derivation and to populate
    /// `ComposeProject.fileURL` / `ComposeProject.id` — the text is not re-read from disk.
    ///
    /// - Throws: `ComposeError.parseFailed` when the YAML is malformed or has no `services:` key.
    static func parse(text: String, fileURL: URL) throws -> ComposeProject {
        let stub: ComposeFileStub
        do {
            stub = try YAMLDecoder().decode(ComposeFileStub.self, from: text)
        } catch {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ComposeError.parseFailed(preview)
        }

        // `services:` key must be present (may be empty, but nil means the file
        // is not a compose file or has no services block at all).
        guard let servicesMap = stub.services else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(200))
            throw ComposeError.parseFailed("Missing 'services:' key — \(preview)")
        }

        let folderURL = fileURL.deletingLastPathComponent()
        let projectName = Self.projectName(name: stub.name, folderURL: folderURL)
        let displayName = stub.name ?? folderURL.lastPathComponent

        // Yams' YAMLDecoder decodes mappings into Swift Dictionaries, which do not
        // preserve insertion order. Sort service names alphabetically for deterministic
        // output (reported in implementation notes).
        let serviceNames = servicesMap.keys.sorted()

        // Build raw image map — null service bodies (nil ServiceStub) have no image.
        var serviceImages: [String: String] = [:]
        for (name, stubOpt) in servicesMap {
            if let image = stubOpt?.image {
                serviceImages[name] = image
            }
        }

        return ComposeProject(
            id: fileURL.standardizedFileURL.path,
            fileURL: fileURL,
            projectName: projectName,
            displayName: displayName,
            serviceNames: serviceNames,
            serviceImages: serviceImages
        )
    }

    /// Reads the file at `fileURL` from disk and delegates to `parse(text:fileURL:)`.
    ///
    /// Sets `isMissing = true` on the returned project when the file cannot be read,
    /// returning a stub so callers can still show the row with a warning.
    static func load(fileURL: URL) throws -> ComposeProject {
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Return a stub with isMissing so the project row stays visible.
            let id = fileURL.standardizedFileURL.path
            let folderURL = fileURL.deletingLastPathComponent()
            let projectName = Self.projectName(name: nil, folderURL: folderURL)
            let displayName = folderURL.lastPathComponent
            var stub = ComposeProject(
                id: id,
                fileURL: fileURL,
                projectName: projectName,
                displayName: displayName,
                serviceNames: [],
                serviceImages: [:]
            )
            stub.isMissing = true
            return stub
        }
        return try parse(text: text, fileURL: fileURL)
    }

    // MARK: Project-name derivation

    /// Derives the compose project name, mirroring `container-compose`'s `deriveProjectName`.
    ///
    /// - Returns `name` when non-nil and non-empty (the compose file's top-level `name:` wins).
    /// - Otherwise, returns `folderURL.lastPathComponent` with every `.` replaced by `_`.
    ///
    /// This is kept as a `static func` so tests can pin sanitization independently of
    /// full file parsing.
    static func projectName(name: String?, folderURL: URL) -> String {
        if let name, !name.isEmpty {
            return name
        }
        return folderURL.lastPathComponent.replacingOccurrences(of: ".", with: "_")
    }
}
