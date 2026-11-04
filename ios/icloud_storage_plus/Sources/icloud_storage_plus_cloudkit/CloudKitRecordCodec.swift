import CloudKit
import Foundation

/// A channel argument from Dart, or a value from CloudKit, that does not match
/// the bridge's contract.
struct CloudKitSyncInvalidArgument: Error, CustomStringConvertible {
  let message: String

  var description: String { message }
}

/// The engine state passed to start could not be decoded.
struct CloudKitSyncInvalidStateSerialization: Error {
  let underlying: Error
}

/// Converts CloudKit values to and from the plain dictionaries that cross the
/// CloudKit sync channel.
///
/// Binary values are `Data` on this side; the channel glue converts them to and
/// from Flutter's typed data.
@available(iOS 17.0, macOS 14.0, *)
enum CloudKitRecordCodec {
  // MARK: Records

  static func encode(_ record: CKRecord) throws -> [String: Any] {
    var fields: [String: Any] = [:]
    var assets: [String: Any] = [:]
    for key in record.allKeys() {
      let value = record[key]
      if let asset = value as? CKAsset {
        // CloudKit does not download the assets of the server record attached
        // to a serverRecordChanged error, so their fileURL is nil.
        assets[key] = asset.fileURL?.path ?? NSNull()
      } else if let value {
        fields[key] = try encodeFieldValue(value, field: key, of: record)
      }
    }
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return [
      "id": encode(record.recordID),
      "recordType": record.recordType,
      "fields": fields,
      "assets": assets,
      "systemFields": archiver.encodedData,
    ]
  }

  static func decodeRecord(_ value: Any?) throws -> CKRecord {
    let map = try dictionary(value, named: "record")
    let id = try decodeRecordID(map["id"])
    let recordType = try string(map["recordType"], named: "recordType")
    let record: CKRecord
    if let systemFields = map["systemFields"] as? Data {
      let unarchiver = try NSKeyedUnarchiver(forReadingFrom: systemFields)
      unarchiver.requiresSecureCoding = true
      guard let archived = CKRecord(coder: unarchiver) else {
        throw CloudKitSyncInvalidArgument(
          message: "systemFields for \(id.recordName) are not an archived CKRecord"
        )
      }
      unarchiver.finishDecoding()
      record = archived
    } else {
      record = CKRecord(recordType: recordType, recordID: id)
    }
    for (key, value) in try dictionary(map["fields"], named: "fields") {
      if value is NSNull {
        record[key] = nil
      } else {
        record.setObject(try decodeFieldValue(value, field: key), forKey: key)
      }
    }
    for (key, path) in try dictionary(map["assets"], named: "assets") {
      record[key] = CKAsset(fileURL: URL(fileURLWithPath: try string(path, named: key)))
    }
    return record
  }

  private static func encodeFieldValue(_ value: CKRecordValue, field: String, of record: CKRecord) throws -> Any {
    // A Bool arrives as a CFBoolean, which also matches NSNumber. Dart has no
    // matching field type, so reject it with the other unsupported types.
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
      throw unsupportedFieldValue(value, field: field, of: record)
    }
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      // CloudKit stores integers as Int64 and other numbers as Double.
      return CFNumberIsFloatType(number as CFNumber) ? number.doubleValue : number.int64Value
    case let data as Data:
      return data
    case let list as [CKRecordValue]:
      return try list.map { try encodeFieldValue($0, field: field, of: record) }
    default:
      throw unsupportedFieldValue(value, field: field, of: record)
    }
  }

  private static func unsupportedFieldValue(_ value: CKRecordValue, field: String, of record: CKRecord) -> Error {
    CloudKitSyncInvalidArgument(
      message: "Field \(field) of \(record.recordType) record \(record.recordID.zoneID.zoneName)/"
        + "\(record.recordID.recordName) holds a \(type(of: value)), which the bridge does not support"
    )
  }

  private static func decodeFieldValue(_ value: Any, field: String) throws -> __CKRecordObjCValue {
    switch value {
    case let string as String:
      return string as NSString
    case let number as NSNumber:
      return number
    case let data as Data:
      return data as NSData
    case let list as [Any]:
      return try list.map { try decodeFieldValue($0, field: field) } as NSArray
    default:
      throw CloudKitSyncInvalidArgument(
        message: "Field \(field) holds a \(type(of: value)), which the bridge does not support"
      )
    }
  }

  // MARK: IDs and pending changes

  static func encode(_ id: CKRecord.ID) -> [String: Any] {
    ["zoneName": id.zoneID.zoneName, "recordName": id.recordName]
  }

  static func decodeRecordID(_ value: Any?) throws -> CKRecord.ID {
    let map = try dictionary(value, named: "id")
    return CKRecord.ID(
      recordName: try string(map["recordName"], named: "recordName"),
      zoneID: CKRecordZone.ID(zoneName: try string(map["zoneName"], named: "zoneName"))
    )
  }

  static func encode(_ change: CKSyncEngine.PendingRecordZoneChange) -> [String: Any]? {
    switch change {
    case .saveRecord(let id):
      return ["type": "save", "id": encode(id)]
    case .deleteRecord(let id):
      return ["type": "delete", "id": encode(id)]
    @unknown default:
      return nil
    }
  }

  static func decodePendingRecordZoneChanges(_ value: Any?) throws -> [CKSyncEngine.PendingRecordZoneChange] {
    try list(value, named: "changes").map { item in
      let map = try dictionary(item, named: "change")
      let id = try decodeRecordID(map["id"])
      switch map["type"] as? String {
      case "save": return .saveRecord(id)
      case "delete": return .deleteRecord(id)
      default: throw CloudKitSyncInvalidArgument(message: "Unknown pending change type \(map["type"] ?? "nil")")
      }
    }
  }

  static func decodePendingDatabaseChanges(_ value: Any?) throws -> [CKSyncEngine.PendingDatabaseChange] {
    try list(value, named: "changes").map { item in
      let map = try dictionary(item, named: "change")
      let zoneID = CKRecordZone.ID(zoneName: try string(map["zoneName"], named: "zoneName"))
      switch map["type"] as? String {
      case "saveZone": return .saveZone(CKRecordZone(zoneID: zoneID))
      case "deleteZone": return .deleteZone(zoneID)
      default: throw CloudKitSyncInvalidArgument(message: "Unknown database change type \(map["type"] ?? "nil")")
      }
    }
  }

  /// Decodes Dart's reply to `nextRecordZoneChangeBatch`.
  static func decodeBatch(_ value: Any?) throws -> (recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID]) {
    let map = try dictionary(value, named: "batch")
    return (
      try list(map["recordsToSave"], named: "recordsToSave").map { try decodeRecord($0) },
      try list(map["recordIDsToDelete"], named: "recordIDsToDelete").map { try decodeRecordID($0) }
    )
  }

  // MARK: Events

  /// Encodes an engine event for Dart, or returns nil for an event the bridge
  /// does not forward.
  static func encode(_ event: CKSyncEngine.Event) throws -> [String: Any]? {
    switch event {
    case .stateUpdate(let update):
      let json = try JSONEncoder().encode(update.stateSerialization)
      return ["type": "stateUpdate", "stateSerialization": String(decoding: json, as: UTF8.self)]

    case .accountChange(let change):
      switch change.changeType {
      case .signIn(let currentUser):
        return ["type": "accountChange", "changeType": "signIn", "currentUserRecordName": currentUser.recordName]
      case .signOut(let previousUser):
        return ["type": "accountChange", "changeType": "signOut", "previousUserRecordName": previousUser.recordName]
      case .switchAccounts(let previousUser, let currentUser):
        return [
          "type": "accountChange",
          "changeType": "switchAccounts",
          "previousUserRecordName": previousUser.recordName,
          "currentUserRecordName": currentUser.recordName,
        ]
      @unknown default:
        return nil
      }

    case .fetchedDatabaseChanges(let changes):
      return [
        "type": "fetchedDatabaseChanges",
        "modifiedZoneNames": changes.modifications.map(\.zoneID.zoneName),
        "deletions": changes.deletions.map { deletion -> [String: Any] in
          let reason: String
          switch deletion.reason {
          case .deleted: reason = "deleted"
          case .purged: reason = "purged"
          case .encryptedDataReset: reason = "encryptedDataReset"
          @unknown default: reason = "unknown"
          }
          return ["zoneName": deletion.zoneID.zoneName, "reason": reason]
        },
      ]

    case .fetchedRecordZoneChanges(let changes):
      return [
        "type": "fetchedRecordZoneChanges",
        "modifications": try changes.modifications.map { try encode($0.record) },
        "deletions": changes.deletions.map { ["id": encode($0.recordID), "recordType": $0.recordType] },
      ]

    case .sentDatabaseChanges(let sent):
      return [
        "type": "sentDatabaseChanges",
        "savedZoneNames": sent.savedZones.map(\.zoneID.zoneName),
        "failedZoneSaves": try sent.failedZoneSaves.map {
          ["zoneName": $0.zone.zoneID.zoneName, "error": try encode($0.error)]
        },
        "deletedZoneNames": sent.deletedZoneIDs.map(\.zoneName),
        "failedZoneDeletes": try sent.failedZoneDeletes.map {
          ["zoneName": $0.key.zoneName, "error": try encode($0.value)]
        },
      ]

    case .sentRecordZoneChanges(let sent):
      return [
        "type": "sentRecordZoneChanges",
        "savedRecords": try sent.savedRecords.map { try encode($0) },
        "failedRecordSaves": try sent.failedRecordSaves.map {
          ["record": try encode($0.record), "error": try encode($0.error)]
        },
        "deletedRecordIDs": sent.deletedRecordIDs.map { encode($0) },
        "failedRecordDeletes": try sent.failedRecordDeletes.map {
          ["id": encode($0.key), "error": try encode($0.value)]
        },
      ]

    case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
      .didFetchChanges, .willSendChanges, .didSendChanges:
      return nil

    @unknown default:
      return nil
    }
  }

  static func encode(_ error: CKError) throws -> [String: Any] {
    var map: [String: Any] = ["code": error.errorCode, "message": error.localizedDescription]
    if let serverRecord = error.serverRecord {
      map["serverRecord"] = try encode(serverRecord)
    }
    return map
  }

  /// Maps a bridge failure to the code, message, and details of the
  /// `FlutterError` that Dart turns into a `CloudKitSyncException`.
  static func encode(failure error: Error) -> (code: String, message: String?, details: [String: Any]?) {
    switch error {
    case let error as CloudKitSyncInvalidArgument:
      return ("invalidArgument", error.message, nil)
    case let error as CloudKitSyncInvalidStateSerialization:
      return ("invalidStateSerialization", "\(error.underlying)", nil)
    case let error as CloudKitSyncEngineNotRunning:
      return ("engineNotRunning", error.reason, nil)
    case let error as CloudKitSyncMissingAsset:
      return ("missingAsset", "The record has no asset in \(error.field).", nil)
    default:
      let nsError = error as NSError
      return ("nativeError", nsError.localizedDescription, ["domain": nsError.domain, "code": nsError.code])
    }
  }

  // MARK: Argument helpers

  static func dictionary(_ value: Any?, named name: String) throws -> [String: Any] {
    guard let map = value as? [String: Any] else {
      throw CloudKitSyncInvalidArgument(message: "\(name) must be a map")
    }
    return map
  }

  static func list(_ value: Any?, named name: String) throws -> [Any] {
    guard let list = value as? [Any] else {
      throw CloudKitSyncInvalidArgument(message: "\(name) must be a list")
    }
    return list
  }

  static func string(_ value: Any?, named name: String) throws -> String {
    guard let string = value as? String else {
      throw CloudKitSyncInvalidArgument(message: "\(name) must be a string")
    }
    return string
  }
}
