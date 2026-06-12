import Foundation

// MARK: - ComposeProjectStore

/// Persists the list of registered compose-file paths in `UserDefaults`.
///
/// The store knows paths only — reparsing into `ComposeProject` values is the
/// view model's responsibility (happens on each refresh). This keeps the store
/// simple, synchronous, and easily testable.
///
/// **Defaults key**: `"composeProjectPaths"` (JSON-encoded `[String]`).
final class ComposeProjectStore: @unchecked Sendable {

    // MARK: - Configuration

    private let defaults: UserDefaults
    private static let key = "composeProjectPaths"

    // MARK: - Init

    /// Creates a store backed by the given `UserDefaults` instance.
    ///
    /// Pass a suite-named instance in tests so each suite starts clean without
    /// touching `UserDefaults.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Returns the currently registered compose-file paths in registration order.
    func paths() -> [String] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    /// Registers the compose file at `url`.
    ///
    /// Deduplicates by `standardizedFileURL.path` — adding the same file twice (even
    /// with different representations of the same path) is a no-op.
    func add(_ url: URL) {
        let canonical = url.standardizedFileURL.path
        var current = paths()
        guard !current.contains(canonical) else { return }
        current.append(canonical)
        save(current)
    }

    /// Removes the project whose `id` (absolute path) matches `id`.
    func remove(id: String) {
        let current = paths().filter { $0 != id }
        save(current)
    }

    // MARK: - Private helpers

    private func save(_ paths: [String]) {
        if let data = try? JSONEncoder().encode(paths) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
