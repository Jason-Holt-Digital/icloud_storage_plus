import CloudKit
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
    XCTAssertEqual((map["assets"] as? [String: String])?["cover"], assetURL.path)

    let decoded = try CloudKitRecordCodec.decodeRecord(map)
    XCTAssertEqual(decoded.recordID, record.recordID)
    XCTAssertEqual(decoded.recordType, "Book")
    XCTAssertEqual(decoded["title"] as? String, "Tome")
    XCTAssertEqual(decoded["pageCount"] as? Int64, 320)
    XCTAssertEqual(decoded["bytes"] as? Data, Data([9, 8]))
    XCTAssertEqual(decoded["tags"] as? [String], ["a", "b"])
    XCTAssertEqual((decoded["cover"] as? CKAsset)?.fileURL, assetURL)
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
    let map: [String: Any] = [
      "id": ["zoneName": "Library", "recordName": "book-1"],
      "recordType": "Book",
      "fields": [String: Any](),
      "assets": [String: String](),
      "systemFields": Data("not an archive".utf8),
    ]

    XCTAssertThrowsError(try CloudKitRecordCodec.decodeRecord(map))
  }

  func testEncodingRejectsUnsupportedFieldValues() {
    let record = CKRecord(recordType: "Book", recordID: CKRecord.ID(recordName: "book-1", zoneID: zoneID))
    record["openedAt"] = Date()

    XCTAssertThrowsError(try CloudKitRecordCodec.encode(record)) { error in
      XCTAssertTrue(error is CloudKitSyncInvalidArgument)
    }
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

    XCTAssertThrowsError(try CloudKitRecordCodec.decodePendingRecordZoneChanges(changes))
    XCTAssertThrowsError(try CloudKitRecordCodec.decodePendingDatabaseChanges(changes))
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
