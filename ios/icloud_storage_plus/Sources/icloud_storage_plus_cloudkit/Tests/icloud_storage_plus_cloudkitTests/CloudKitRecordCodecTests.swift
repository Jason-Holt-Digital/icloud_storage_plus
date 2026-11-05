import CloudKit
import CoreLocation
import XCTest

@testable import icloud_storage_plus_cloudkit

final class CloudKitRecordCodecTests: XCTestCase {
  private let zoneID = CKRecordZone.ID(zoneName: "Library")

  func testRecordRoundTripKeepsFieldTypesAndAssets() throws {
    let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cover.png")
    try Data([1, 2, 3]).write(to: assetURL)
    defer { try? FileManager.default.removeItem(at: assetURL) }
    let record = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
    record["title"] = "Tome"
    record["pageCount"] = 320 as Int64
    record["aspect"] = 1.0 as Double
    record["bytes"] = Data([9, 8])
    record["tags"] = ["a", "b"] as [String]
    record["cover"] = CKAsset(fileURL: assetURL)

    let map = try CloudKitRecordCodec.encode(record)
    let fields = try XCTUnwrap(map["fields"] as? [String: Any])
    XCTAssertEqual(fields["title"] as? String, "Tome")
    XCTAssertEqual(fields["pageCount"] as? Int64, 320)
    XCTAssertTrue(fields["aspect"] is Double, "a whole-number Double must stay a Double")
    XCTAssertEqual(fields["bytes"] as? Data, Data([9, 8]))
    XCTAssertEqual(fields["tags"] as? [String], ["a", "b"])
    XCTAssertNil(fields["cover"], "assets travel separately from fields")
    XCTAssertEqual((map["assets"] as? [String: Any])?["cover"] as? String, assetURL.path)

    let decoded = try CloudKitRecordCodec.decodeRecord(map)
    XCTAssertEqual(decoded.recordID, record.recordID)
    XCTAssertEqual(decoded.recordType, "Book")
    XCTAssertEqual(decoded["title"] as? String, "Tome")
    XCTAssertEqual(decoded["pageCount"] as? Int64, 320)
    XCTAssertEqual(decoded["bytes"] as? Data, Data([9, 8]))
    XCTAssertEqual(decoded["tags"] as? [String], ["a", "b"])
    XCTAssertEqual((decoded["cover"] as? CKAsset)?.fileURL, assetURL)
  }

  func testAccountStatusNamesMatchTheDartEnum() {
    XCTAssertEqual(CloudKitRecordCodec.encode(CKAccountStatus.available), "available")
    XCTAssertEqual(CloudKitRecordCodec.encode(CKAccountStatus.noAccount), "noAccount")
    XCTAssertEqual(CloudKitRecordCodec.encode(CKAccountStatus.restricted), "restricted")
    XCTAssertEqual(
      CloudKitRecordCodec.encode(CKAccountStatus.temporarilyUnavailable), "temporarilyUnavailable"
    )
    XCTAssertEqual(CloudKitRecordCodec.encode(CKAccountStatus.couldNotDetermine), "couldNotDetermine")
  }

  func testDecodingFromSystemFieldsSetsOnlyTheGivenFields() throws {
    let record = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
    record["title"] = "Old title"
    record["subtitle"] = "Kept on the server"
    var map = try CloudKitRecordCodec.encode(record)
    map["fields"] = ["title": "New title", "removed": NSNull()]
    map["assets"] = [String: String]()

    let decoded = try CloudKitRecordCodec.decodeRecord(map)

    XCTAssertEqual(decoded.recordID, record.recordID)
    XCTAssertEqual(decoded["title"] as? String, "New title")
    XCTAssertNil(decoded["subtitle"], "archived system fields carry no field values")
    XCTAssertEqual(Set(decoded.changedKeys()), ["title", "removed"])
  }

  func testDecodingRejectsSystemFieldsThatAreNotARecord() throws {
    func record(systemFields: Data) -> [String: Any] {
      [
        "id": ["zoneName": "Library", "recordName": "book-1"],
        "recordType": "Book",
        "fields": [String: Any](),
        "assets": [String: String](),
        "systemFields": systemFields,
      ]
    }
    let archivedString = try NSKeyedArchiver.archivedData(withRootObject: "Book" as NSString, requiringSecureCoding: true)

    XCTAssertThrowsError(try CloudKitRecordCodec.decodeRecord(record(systemFields: archivedString))) { error in
      XCTAssertTrue(error is CloudKitSyncInvalidArgument, "\(error)")
    }
    XCTAssertThrowsError(try CloudKitRecordCodec.decodeRecord(record(systemFields: Data("not an archive".utf8)))) {
      error in
      XCTAssertEqual((error as? CocoaError)?.code, .coderReadCorrupt, "\(error)")
    }
  }

  func testEncodingRejectsUnsupportedFieldValuesNamingTheRecordAndField() {
    let values: [String: CKRecordValue] = [
      "openedAt": Date() as NSDate,
      "read": true as NSNumber,
      "flags": [true, false] as NSArray,
      "series": CKRecord.Reference(recordID: CKRecord.ID(recordName: "s", zoneID: zoneID), action: .none),
      "place": CLLocation(latitude: 0, longitude: 0),
    ]
    for (field, value) in values {
      let record = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
      record[field] = value

      XCTAssertThrowsError(try CloudKitRecordCodec.encode(record), field) { error in
        let message = (error as? CloudKitSyncInvalidArgument)?.message ?? "\(error)"
        XCTAssertTrue(message.contains("Field \(field) of Book record Library/book-1"), message)
      }
    }
  }

  func testAnAssetThatWasNotDownloadedEncodesAsNull() throws {
    let record = try serverRecordWithUndownloadedAsset()
    XCTAssertNil((record["cover"] as? CKAsset)?.fileURL)

    let map = try CloudKitRecordCodec.encode(record)

    let assets = try XCTUnwrap(map["assets"] as? [String: Any])
    XCTAssertTrue(assets["cover"] is NSNull, "\(assets)")
  }

  /// Builds the record CloudKit attaches to a serverRecordChanged error,
  /// whose assets it does not download. CKAsset has no public initializer
  /// without a file, so this archives a record and drops the asset's URL.
  private func serverRecordWithUndownloadedAsset() throws -> CKRecord {
    let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1]).write(to: assetURL)
    defer { try? FileManager.default.removeItem(at: assetURL) }
    let record = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
    record["cover"] = CKAsset(fileURL: assetURL)
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encode(with: archiver)
    archiver.finishEncoding()
    let archive = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: archiver.encodedData,
        options: .mutableContainers,
        format: nil
      ) as? NSDictionary
    )
    for case let object as NSMutableDictionary in try XCTUnwrap(archive["$objects"] as? NSArray) {
      object.removeObject(forKey: "AssetFileURL")
    }
    let unarchiver = try NSKeyedUnarchiver(
      forReadingFrom: PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
    )
    unarchiver.requiresSecureCoding = true
    return try XCTUnwrap(CKRecord(coder: unarchiver))
  }

  func testPendingRecordZoneChangesRoundTrip() throws {
    let id = CKRecord.ID(recordName: "book-1", zoneID: zoneID)
    let encoded = [CKSyncEngine.PendingRecordZoneChange.saveRecord(id), .deleteRecord(id)]
      .compactMap { CloudKitRecordCodec.encode($0) }

    let decoded = try CloudKitRecordCodec.decodePendingRecordZoneChanges(encoded)

    XCTAssertEqual(decoded, [.saveRecord(id), .deleteRecord(id)])
  }

  func testPendingChangesRejectUnknownTypes() {
    let changes: [[String: Any]] = [["type": "move", "id": ["zoneName": "Library", "recordName": "a"]]]

    XCTAssertThrowsError(try CloudKitRecordCodec.decodePendingRecordZoneChanges(changes)) { error in
      XCTAssertTrue(error is CloudKitSyncInvalidArgument, "\(error)")
    }
    XCTAssertThrowsError(try CloudKitRecordCodec.decodePendingDatabaseChanges(changes)) { error in
      XCTAssertTrue(error is CloudKitSyncInvalidArgument, "\(error)")
    }
  }

  func testPendingDatabaseChangesDecode() throws {
    let decoded = try CloudKitRecordCodec.decodePendingDatabaseChanges([
      ["type": "saveZone", "zoneName": "Library"],
      ["type": "deleteZone", "zoneName": "Blobs"],
    ])

    XCTAssertEqual(decoded, [.saveZone(CKRecordZone(zoneID: zoneID)), .deleteZone(CKRecordZone.ID(zoneName: "Blobs"))])
  }

  func testBatchDecodesRecordsAndDeletes() throws {
    let batch = try CloudKitRecordCodec.decodeBatch([
      "recordsToSave": [
        [
          "id": ["zoneName": "Library", "recordName": "book-1"],
          "recordType": "Book",
          "fields": ["title": "Tome"],
          "assets": [String: String](),
        ] as [String: Any]
      ],
      "recordIDsToDelete": [["zoneName": "Library", "recordName": "book-2"]],
    ])

    XCTAssertEqual(batch.recordsToSave.map(\.recordID.recordName), ["book-1"])
    XCTAssertEqual(batch.recordsToSave.first?["title"] as? String, "Tome")
    XCTAssertEqual(batch.recordIDsToDelete, [CKRecord.ID(recordName: "book-2", zoneID: zoneID)])
  }

  func testErrorCarriesCodeAndServerRecord() throws {
    let serverRecord = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
    let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord])

    let map = try CloudKitRecordCodec.encode(error)

    XCTAssertEqual(map["code"] as? Int, CKError.Code.serverRecordChanged.rawValue)
    let encodedServerRecord = try XCTUnwrap(map["serverRecord"] as? [String: Any])
    XCTAssertEqual((encodedServerRecord["id"] as? [String: Any])?["recordName"] as? String, "book-1")
  }
}

/// The codes must match the constants on Dart's `CloudKitSyncException`.
final class CloudKitFailureEncodingTests: XCTestCase {
  func testInvalidArgument() {
    let failure = CloudKitRecordCodec.encode(failure: CloudKitSyncInvalidArgument(message: "id must be a map"))

    XCTAssertEqual(failure.code, "invalidArgument")
    XCTAssertEqual(failure.message, "id must be a map")
    XCTAssertNil(failure.details)
  }

  func testInvalidStateSerialization() {
    let underlying: Error = CocoaError(.coderReadCorrupt)
    let failure = CloudKitRecordCodec.encode(failure: CloudKitSyncInvalidStateSerialization(underlying: underlying))

    XCTAssertEqual(failure.code, "invalidStateSerialization")
    XCTAssertEqual(failure.message, "\(underlying)")
    XCTAssertNil(failure.details)
  }

  func testEngineNotRunning() {
    let failure = CloudKitRecordCodec.encode(
      failure: CloudKitSyncEngineNotRunning(reason: "An event was not handled: Dart error delegateError: boom")
    )

    XCTAssertEqual(failure.code, "engineNotRunning")
    XCTAssertEqual(failure.message, "An event was not handled: Dart error delegateError: boom")
    XCTAssertNil(failure.details)
  }

  func testMissingAsset() {
    let failure = CloudKitRecordCodec.encode(failure: CloudKitSyncMissingAsset(field: "data"))

    XCTAssertEqual(failure.code, "missingAsset")
    XCTAssertEqual(failure.message, "The record has no asset in data.")
    XCTAssertNil(failure.details)
  }

  func testNativeErrorKeepsDomainAndCode() throws {
    let error = CKError(.quotaExceeded)
    let failure = CloudKitRecordCodec.encode(failure: error)

    XCTAssertEqual(failure.code, "nativeError")
    XCTAssertEqual(failure.message, error.localizedDescription)
    let details = try XCTUnwrap(failure.details)
    XCTAssertEqual(details["domain"] as? String, CKError.errorDomain)
    XCTAssertEqual(details["code"] as? Int, CKError.Code.quotaExceeded.rawValue)
  }
}

final class CloudKitSyncBridgeScopeTests: XCTestCase {
  private let library = CKRecordZone.ID(zoneName: "Library")
  private let blobs = CKRecordZone.ID(zoneName: "Blobs")
  private let other = CKRecordZone.ID(zoneName: "Other")

  func testExcludedZonesAreRemovedFromEveryScope() {
    XCTAssertEqual(CloudKitSyncBridge.scope(.all, excluding: [blobs]), .allExcluding([blobs]))
    XCTAssertEqual(
      CloudKitSyncBridge.scope(.allExcluding([other, blobs]), excluding: [blobs]),
      .allExcluding([other, blobs])
    )
    XCTAssertEqual(CloudKitSyncBridge.scope(.zoneIDs([library, blobs]), excluding: [blobs]), .zoneIDs([library]))
  }

  func testNoExcludedZonesKeepsTheScope() {
    XCTAssertEqual(CloudKitSyncBridge.scope(.all, excluding: []), .all)
  }
}
