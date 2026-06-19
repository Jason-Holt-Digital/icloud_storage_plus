import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class UbiquitousItemMaterializerTests: XCTestCase {
    private let itemURL = URL(fileURLWithPath: "/tmp/container/Documents/journal.json")

    /// VAL-MUT-030: an intentional open of a not-yet-`.current` item
    /// requests download exactly once.
    func testNotCurrentRequestsDownloadExactlyOnce() throws {
        var startDownloadCount = 0

        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .notDownloaded },
            startDownloading: { _ in
                startDownloadCount += 1
            }
        )

        let status = try materializer.requestMaterializationIfNeeded(
            at: itemURL
        )

        XCTAssertEqual(status, .notDownloaded)
        XCTAssertEqual(
            startDownloadCount, 1,
            "startDownloading must be invoked exactly once for a "
                + "not-yet-current item"
        )
    }

    /// VAL-MUT-030: a `.current` item does NOT request download.
    func testCurrentDoesNotRequestDownload() throws {
        var startDownloadCount = 0

        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .current },
            startDownloading: { _ in
                startDownloadCount += 1
            }
        )

        let status = try materializer.requestMaterializationIfNeeded(
            at: itemURL
        )

        XCTAssertEqual(status, .current)
        XCTAssertEqual(startDownloadCount, 0)
    }

    /// VAL-MUT-032: each normal lifecycle state requests download (or
    /// returns) and raises NO error.
    func testNormalLifecycleStatesNeverBecomeErrors() throws {
        let normalStates: [UbiquitousItemMaterializer.Status] = [
            .notDownloaded,
            .downloading,
            .placeholder,
            .downloaded,
        ]

        for state in normalStates {
            var startDownloadCount = 0
            let materializer = UbiquitousItemMaterializer(
                downloadStatus: { _ in state },
                startDownloading: { _ in
                    startDownloadCount += 1
                }
            )

            XCTAssertNoThrow(
                try materializer.requestMaterializationIfNeeded(
                    at: itemURL
                ),
                "normal lifecycle state \(state) must not raise an error"
            )
            // Non-current states request download exactly once.
            if state != .current {
                XCTAssertEqual(startDownloadCount, 1)
            }
        }
    }

    /// VAL-MUT-031: a download that does not complete imposes no
    /// timeout/deadline error and installs no watchdog. The request
    /// returns immediately after requesting download.
    func testMaterializationIsRequestNotDeadline() throws {
        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .notDownloaded },
            startDownloading: { _ in
                // Record the request and return immediately. No
                // completion signal, no watchdog — the caller must not
                // wait or time out.
            }
        )

        let started = Date()
        let status = try materializer.requestMaterializationIfNeeded(
            at: itemURL
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(status, .notDownloaded)
        XCTAssertLessThan(
            elapsed, 1.0,
            "requestMaterializationIfNeeded must return immediately "
                + "(request, not a deadline); no timeout/watchdog"
        )
    }

    /// VAL-MUT-033: a write/open against a not-yet-`.current` item
    /// requests download and raises no conflict/lifecycle error. The
    /// materializer surfaces only the status (never a conflict error).
    func testWriteAgainstNotCurrentRequestsDownloadNoConflictError() throws {
        var requestedURL: URL?
        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .placeholder },
            startDownloading: { url in
                requestedURL = url
            }
        )

        let status = try materializer.requestMaterializationIfNeeded(
            at: itemURL
        )

        XCTAssertEqual(status, .placeholder)
        XCTAssertEqual(requestedURL, itemURL)
        // No conflict/lifecycle error is thrown (XCTAssertNoThrow above).
    }

    /// A `.downloading` item still requests download (idempotent request)
    /// and does not error.
    func testDownloadingStateRequestsAgainWithoutError() throws {
        var startDownloadCount = 0
        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .downloading },
            startDownloading: { _ in
                startDownloadCount += 1
            }
        )

        let status = try materializer.requestMaterializationIfNeeded(
            at: itemURL
        )

        XCTAssertEqual(status, .downloading)
        XCTAssertEqual(startDownloadCount, 1)
    }

    /// A genuine `startDownloading` failure surfaces as a thrown error
    /// (the status check itself never throws; only the request can).
    func testStartDownloadingFailureSurfacesTypedError() {
        struct RequestFailed: Error {}

        let materializer = UbiquitousItemMaterializer(
            downloadStatus: { _ in .notDownloaded },
            startDownloading: { _ in throw RequestFailed() }
        )

        XCTAssertThrowsError(
            try materializer.requestMaterializationIfNeeded(at: itemURL)
        ) { error in
            XCTAssertTrue(error is RequestFailed)
        }
    }
}
