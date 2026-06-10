import Foundation

// MARK: - ProcessResult

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// MARK: - ProcessRunning protocol

protocol ProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult
}

// MARK: - ProcessRunner

/// A concrete `ProcessRunning` implementation backed by `Foundation.Process`.
///
/// Pipe reads are started on background threads concurrently with the process so
/// that a chatty process can never fill a pipe buffer and deadlock while we wait
/// for it to exit.  Non-zero exit codes are NOT thrown — they are returned inside
/// `ProcessResult` so callers can inspect stderr before deciding what to do.
struct ProcessRunner: ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            // Buffer accumulator: a reference type whose mutation is serialised by
            // its own lock so it is safe to share across the readabilityHandler and
            // terminationHandler closures without escaping a `var` across concurrency
            // boundaries (which Swift 6 forbids).
            final class PipeBuffer: @unchecked Sendable {
                private var data = Data()
                private let lock = NSLock()

                func append(_ chunk: Data) {
                    lock.withLock { data.append(chunk) }
                }

                func consume() -> Data {
                    lock.withLock {
                        let d = data
                        data = Data()
                        return d
                    }
                }

                func current() -> Data {
                    lock.withLock { data }
                }
            }

            let stdoutBuffer = PipeBuffer()
            let stderrBuffer = PipeBuffer()

            // All Process interaction is confined to this synchronous scope so we
            // never expose the non-Sendable Process across concurrency boundaries.
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            // Inherit the caller's environment or use an explicit override.
            if let environment {
                process.environment = environment
            }

            // Provide EOF on stdin so interactive prompts that read from stdin
            // fail immediately rather than hanging the process.
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // These handlers run on arbitrary threads but only mutate their
            // respective PipeBuffer (a Sendable reference type with internal locking).
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stdoutBuffer.append(chunk)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stderrBuffer.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                // Stop the readability handlers so they no longer fire.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Drain any remaining bytes that arrived between the last
                // readabilityHandler invocation and the pipe being closed.
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if !remainingStdout.isEmpty { stdoutBuffer.append(remainingStdout) }
                if !remainingStderr.isEmpty { stderrBuffer.append(remainingStderr) }

                let stdout = String(data: stdoutBuffer.current(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrBuffer.current(), encoding: .utf8) ?? ""

                continuation.resume(returning: ProcessResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: proc.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                // Clear handlers before resuming to avoid a dangling reference.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
