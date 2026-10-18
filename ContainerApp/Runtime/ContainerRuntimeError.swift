import Foundation

// MARK: - Runtime errors

enum ContainerRuntimeError: Error {
    case notFound(id: String)
    case commandFailed(exitCode: Int32, stderr: String)
    /// A container-system API request failed; `message` is the runtime's own explanation.
    case requestFailed(message: String)
    case cliNotFound
    case composeCLINotFound
    case systemNotRunning
}

// MARK: - LocalizedError

extension ContainerRuntimeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Apple container CLI was not found. Install Apple container, then configure the path in Settings."

        case .composeCLINotFound:
            return "container-compose was not found. Install it with: brew install container-compose, then configure the path in Settings."

        case .systemNotRunning:
            return "Container system is not running."

        case .notFound(let id):
            return "Container \"\(id)\" was not found."

        case .commandFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) : trimmed
            return "Command failed (exit \(exitCode)): \(preview)"

        case .requestFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
            return "Container system request failed: \(preview)"
        }
    }
}
