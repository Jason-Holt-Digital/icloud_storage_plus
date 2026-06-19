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
    ///
    /// `persistentIdentifier` is an opaque `Any` whose concrete runtime
    /// type is a private Apple class. Archiving with `NSKeyedArchiver`
    /// and Base64-encoding the result produces a stable, round-trippable
    /// string for any valid `NSFileVersion`.
    static func identifier(for version: NSFileVersion) -> String {
        archiveIdentifier(version.persistentIdentifier) ?? ""
    }

    /// Archives an opaque `NSFileVersion.persistentIdentifier` into a
    /// deterministic base64 string. Returns nil if the identifier cannot
    /// be archived. `persistentIdentifier` is an opaque `Any` backed by a
    /// private Apple class; archiving (rather than casting to
    /// `[String: Any]`) is the only way to produce a stable, round-
    /// trippable identifier for version selection on copy-out.
    static func archiveIdentifier(_ identifier: Any) -> String? {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: identifier,
            requiringSecureCoding: false
        ) else {
            return nil
        }
        return data.base64EncodedString()
    }

    /// Unarchives a base64 identifier back into the opaque
    /// `persistentIdentifier` object. Used for diagnostics/tests; copy-out
    /// matches by re-archiving each candidate version, not by unarchiving.
    static func unarchiveIdentifier(_ string: String) -> Any? {
        guard let data = Data(base64Encoded: string) else {
            return nil
        }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        else {
            return nil
        }
        unarchiver.requiresSecureCoding = false
        let result = unarchiver.decodeObject(
            forKey: NSKeyedArchiveRootObjectKey
        )
        unarchiver.finishDecoding()
        return result
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
            // The caller passes back a descriptor `identifier` produced
            // by `identifier(for:)`. Match by recomputing each candidate
            // version's serialized identifier and comparing by string
            // equality (deterministic, independent of the opaque
            // persistentIdentifier type's `isEqual`). An empty identifier
            // (archival failure / nil persistentIdentifier) cannot
            // reliably select a version, so surface a typed not-found
            // error rather than falsely matching the first version that
            // also serializes to empty.
            guard !identifier.isEmpty else {
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
