import Foundation

/// Proactive download / materialization request seam.
///
/// A write/open against a not-yet-`.current` ubiquity item REQUESTS a
/// download via `FileManager.startDownloadingUbiquitousItem(at:)`. This
/// is a REQUEST, not a deadline: the caller returns immediately and
/// imposes no artificial timeout/watchdog. Normal iCloud lifecycle
/// states (notDownloaded, downloading, placeholder) NEVER become plugin
/// errors — Apple owns sync/materialization.
///
/// DI-via-closures (same idiom as `CoordinatedReplaceWriter`): XCTest
/// injects deterministic metadata states and a recording
/// `startDownloading` closure; `static let live` binds the real
/// `FileManager` ubiquity APIs. `URLResourceValues` ubiquitous-item
/// keys exist on iOS 13 / macOS 10.15 (the plugin deployment floor) —
/// no availability guard required.
struct UbiquitousItemMaterializer {
    /// Materialization state of a ubiquity item.
    enum Status: Sendable, Equatable {
        /// Local content is fully current.
        case current
        /// Downloaded but not yet current.
        case downloaded
        /// Not yet downloaded.
        case notDownloaded
        /// Download is in progress.
        case downloading
        /// Dataless APFS placeholder (treated as not-yet-current).
        case placeholder
    }

    typealias DownloadStatusProvider = (URL) -> Status
    typealias StartDownloading = (URL) throws -> Void

    let downloadStatus: DownloadStatusProvider
    let startDownloading: StartDownloading

    /// Requests proactive download if the item is not yet `.current`.
    /// Returns the item's status. The status check NEVER throws —
    /// normal lifecycle states are not errors. The `startDownloading`
    /// call is made exactly once for any non-`.current` status (and not
    /// at all for `.current`); genuine request failures surface as
    /// thrown errors, but no timeout/watchdog is installed and the
    /// caller never waits for the download to complete.
    func requestMaterializationIfNeeded(at url: URL) throws -> Status {
        let status = downloadStatus(url)
        if status == .current {
            return .current
        }
        // Request download (best-effort request, not a deadline). The
        // download proceeds asynchronously; the caller does not wait.
        try startDownloading(url)
        return status
    }
}

extension UbiquitousItemMaterializer {
    static let live = UbiquitousItemMaterializer(
        downloadStatus: { url in
            let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .isUbiquitousItemKey,
            ])

            if values?.ubiquitousItemIsDownloading == true {
                return .downloading
            }

            switch values?.ubiquitousItemDownloadingStatus {
            case .current:
                return .current
            case .downloaded:
                return .downloaded
            case .notDownloaded:
                return .notDownloaded
            default:
                return .notDownloaded
            }
        },
        startDownloading: { url in
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    )
}
