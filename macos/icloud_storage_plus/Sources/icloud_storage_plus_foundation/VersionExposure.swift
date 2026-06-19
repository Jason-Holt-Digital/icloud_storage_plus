import Foundation

/// App-owned conflict-version exposure primitives.
///
/// The plugin only EXPOSES `NSFileVersion`s; it never auto-resolves or
/// silently deletes losing versions. The app enumerates unresolved
/// versions, copies losing versions out to caller-provided backup URLs,
/// and marks conflicts resolved only after it has confirmed backups.
///
/// DI-via-closures (same idiom as `CoordinatedReplaceWriter`): XCTest
/// injects deterministic closures; `static let live` binds the real
/// `NSFileVersion` APIs. `NSFileVersion`'s entire surface is available
/// on iOS 13 / macOS 10.15 (the plugin deployment floor) — no
/// availability guard required.
struct VersionExposure {
    /// Stable, round-trippable descriptor for a single unresolved
    /// `NSFileVersion`. `identifier` is opaque to Dart and is passed
    /// back unmodified to select a version for copy-out.
    struct Descriptor: Equatable, Sendable {
        let identifier: String
        let modificationDate: Date?
    }

    /// Enumerates unresolved conflict versions for an item and returns
    /// stable descriptors. An item with no unresolved versions returns
    /// an empty list — never an error (VAL-MUT-022).
    typealias EnumerateUnresolved = (URL) throws -> [Descriptor]

    /// Copies a specific losing version's bytes to a CALLER-PROVIDED
    /// destination URL, leaving the live item untouched (VAL-MUT-019).
    /// On failure: typed error, no partial file at the caller URL, live
    /// item unchanged (VAL-MUT-044).
    typealias CopyVersionOut = (URL, String, URL) throws -> Void

    /// Marks unresolved versions resolved (`isResolved = true`) and,
    /// when `removeOthers` is true, removes the other versions via
    /// `NSFileVersion.removeOtherVersionsOfItem(at:)`. Idempotent and a
    /// no-op when nothing is unresolved (VAL-MUT-045). Invoked ONLY on
    /// explicit app request (VAL-MUT-020).
    typealias MarkConflictResolved = (URL, Bool) throws -> Void

    let enumerateUnresolved: EnumerateUnresolved
    let copyVersionOut: CopyVersionOut
    let markConflictResolved: MarkConflictResolved

    func enumerate(at url: URL) throws -> [Descriptor] {
        try enumerateUnresolved(url)
    }

    func copyOut(
        itemURL: URL,
        identifier: String,
        to destinationURL: URL
    ) throws {
        try copyVersionOut(itemURL, identifier, destinationURL)
    }

    func markResolved(at url: URL, removeOthers: Bool) throws {
        try markConflictResolved(url, removeOthers)
    }
}

extension VersionExposure {
    static let replaceStateErrorDomain =
        CoordinatedReplaceWriter.replaceStateErrorDomain

    /// Deterministic serialization of an `NSFileVersion`'s
    /// `persistentIdentifier` so the descriptor `identifier` round-trips
    /// through Dart and back into a version match on copy-out.
    static func identifier(for version: NSFileVersion) -> String {
        let pid = version.persistentIdentifier as? [String: Any] ?? [:]
        return pid.keys.sorted().map { "\($0):\(String(describing: pid[$0]))" }
            .joined(separator: "|")
    }

    /// Typed error for "no unresolved version matched the identifier"
    /// (version-exposure failure). Maps to `E_CONFLICT` via
    /// `nativeCodeError` (repurposed from the deleted auto-resolve
    /// producer — VAL-MUT-011).
    static func versionNotFoundError(itemURL: URL) -> NSError {
        NSError(
            domain: replaceStateErrorDomain,
            code: CoordinatedReplaceWriter.conflictReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "No unresolved conflict version matched the requested "
                    + "identifier for \(itemURL.lastPathComponent).",
            ]
        )
    }

    static let live = VersionExposure(
        enumerateUnresolved: { url in
            guard let versions =
                NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
            else {
                return []
            }
            return versions.map {
                Descriptor(
                    identifier: Self.identifier(for: $0),
                    modificationDate: $0.modificationDate
                )
            }
        },
        copyVersionOut: { itemURL, identifier, destinationURL in
            guard let versions =
                NSFileVersion.unresolvedConflictVersionsOfItem(at: itemURL)
            else {
                throw versionNotFoundError(itemURL: itemURL)
            }
            guard let version = versions.first(
                where: { Self.identifier(for: $0) == identifier }
            ) else {
                throw versionNotFoundError(itemURL: itemURL)
            }
            // `replaceItem(at:options:)` writes the version's bytes to
            // the caller-provided destination URL. The live item at
            // `itemURL` is NOT modified.
            _ = try version.replaceItem(at: destinationURL, options: [])
        },
        markConflictResolved: { url, removeOthers in
            guard let versions =
                NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
            else {
                // No unresolved versions: idempotent no-op (VAL-MUT-045).
                return
            }
            for version in versions {
                version.isResolved = true
            }
            if removeOthers {
                try NSFileVersion.removeOtherVersionsOfItem(at: url)
            }
        }
    )
}
