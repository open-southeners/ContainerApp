import Foundation

// MARK: - Runtime errors

enum ContainerRuntimeError: Error {
    case notFound(id: String)
    case commandFailed(exitCode: Int32, stderr: String)
    case decodingFailed(raw: String)
    case cliNotFound
    case systemNotRunning
}

// MARK: - LocalizedError

extension ContainerRuntimeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Apple container CLI was not found. Install Apple container, then configure the path in Settings."

        case .systemNotRunning:
            return "Container system is not running."

        case .notFound(let id):
            return "Container \"\(id)\" was not found."

        case .commandFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) : trimmed
            return "Command failed (exit \(exitCode)): \(preview)"

        case .decodingFailed(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
            return "Could not parse CLI output: \(preview)"
        }
    }
}
