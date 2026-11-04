import CloudKit
import Foundation

/// The fetched record has no asset in the requested field.
struct CloudKitSyncMissingAsset: Error {
  let field: String
}

/// Single-record asset transfers in the private database, outside the sync
/// engine.
@available(iOS 17.0, macOS 14.0, *)
enum CloudKitAssetTransfers {
  static func recordExists(in database: CKDatabase, id: CKRecord.ID) async throws -> Bool {
    do {
      let results = try await database.records(for: [id], desiredKeys: [])
      guard let result = results[id] else { return false }
      _ = try result.get()
      return true
    } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
      return false
    }
  }

  /// Saves [source] as the asset in [field] of the record [id], creating the
  /// record's zone when it does not exist yet. An existing record is
  /// overwritten.
  static func upload(
    to database: CKDatabase,
    id: CKRecord.ID,
    recordType: CKRecord.RecordType,
    field: String,
    source: URL
  ) async throws {
    // Saving a zone that already exists succeeds, so the upload does not need
    // to know whether this is the zone's first record.
    let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: id.zoneID)], deleting: [])
    _ = try zones.saveResults[id.zoneID]?.get()
    let record = CKRecord(recordType: recordType, recordID: id)
    record[field] = CKAsset(fileURL: source)
    let records = try await database.modifyRecords(
      saving: [record],
      deleting: [],
      savePolicy: .allKeys,
      atomically: false
    )
    _ = try records.saveResults[id]?.get()
  }

  /// Copies the asset in [field] of the record [id] to [destination],
  /// replacing any file there.
  static func download(
    from database: CKDatabase,
    id: CKRecord.ID,
    field: String,
    destination: URL,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let operation = CKFetchRecordsOperation(recordIDs: [id])
    operation.desiredKeys = [field]
    operation.qualityOfService = .userInitiated
    operation.perRecordProgressBlock = { _, progress in onProgress(progress) }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let outcome = DownloadOutcome()
      operation.perRecordResultBlock = { _, result in
        outcome.result = Result {
          let record = try result.get()
          guard let url = (record[field] as? CKAsset)?.fileURL else {
            throw CloudKitSyncMissingAsset(field: field)
          }
          // The asset file lives in CloudKit's cache, which may be cleared
          // once the operation finishes, so copy it now.
          let fileManager = FileManager.default
          if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
          }
          try fileManager.copyItem(at: url, to: destination)
        }
      }
      operation.fetchRecordsResultBlock = { result in
        switch (outcome.result, result) {
        case (.some(let recordResult), _):
          continuation.resume(with: recordResult)
        case (.none, .failure(let error)):
          continuation.resume(throwing: error)
        case (.none, .success):
          continuation.resume(throwing: CKError(.unknownItem))
        }
      }
      database.add(operation)
    }
  }
}

/// Carries the per-record result to the operation's completion block.
private final class DownloadOutcome: @unchecked Sendable {
  private let lock = NSLock()
  private var storedResult: Result<Void, Error>?

  var result: Result<Void, Error>? {
    get { lock.withLock { storedResult } }
    set { lock.withLock { storedResult = newValue } }
  }
}
