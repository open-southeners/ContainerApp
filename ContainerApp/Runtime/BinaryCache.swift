import Foundation

// MARK: - Binary URL cache (actor for Swift 6 Sendable correctness)

/// Isolated store for the lazily-discovered binary URL of a CLI tool.
/// Using an actor avoids `@unchecked Sendable` while keeping the cache
/// mutation safely serialised across concurrent callers.
///
/// The cache is keyed by the UserDefaults override string that was current
/// when the resolution happened.  When the user edits the setting the key
/// changes and the next call to `resolvedBinaryURL()` will re-run discovery.
actor BinaryCache {
    /// The override key that was active when `resolvedURL` was cached.
    /// `nil` means the cache was populated without a UserDefaults override.
    private var cachedKey: String?
    private var resolvedURL: URL?

    /// Returns the cached URL only when `currentKey` matches the key under
    /// which the URL was originally cached.
    func get(forKey currentKey: String?) -> URL? {
        guard cachedKey == currentKey else { return nil }
        return resolvedURL
    }

    func set(_ url: URL, forKey key: String?) {
        resolvedURL = url
        cachedKey = key
    }
}
