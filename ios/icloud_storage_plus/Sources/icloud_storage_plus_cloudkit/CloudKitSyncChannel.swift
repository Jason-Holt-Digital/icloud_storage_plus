#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import CloudKit
import Foundation

/// The Flutter side of the CloudKit sync bridge: its own method channel, kept
/// apart from document storage.
final class CloudKitSyncChannel: NSObject {
  static let channelName = "icloud_storage_plus/cloudkit_sync"

  private let channel: FlutterMethodChannel
  /// A `CloudKitSyncBridge`, created on first use. Typed as `AnyObject`
  /// because the bridge needs iOS 17 or macOS 14 and this class does not.
  private var bridgeStorage: AnyObject?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = CloudKitSyncChannel(channel: channel)
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 17.0, macOS 14.0, *) else {
      result(
        FlutterError(
          code: "unsupportedPlatformVersion",
          message: "The CloudKit sync bridge requires iOS 17 or macOS 14.",
          details: nil
        )
      )
      return
    }
    let arguments = Self.plainValue(call.arguments) as? [String: Any] ?? [:]
    Task { @MainActor in
      do {
        result(try await self.perform(call.method, arguments))
      } catch {
        result(Self.flutterError(error))
      }
    }
  }

  @available(iOS 17.0, macOS 14.0, *)
  @MainActor
  private func perform(_ method: String, _ arguments: [String: Any]) async throws -> Any? {
    switch method {
    case "start":
      let serialization: CKSyncEngine.State.Serialization?
      if let state = arguments["stateSerialization"] as? String {
        do {
          serialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: Data(state.utf8))
        } catch {
          throw InvalidStateSerialization(underlying: error)
        }
      } else {
        serialization = nil
      }
      await bridge.start(
        containerID: try CloudKitRecordCodec.string(arguments["containerId"], "containerId"),
        stateSerialization: serialization,
        excludedZoneNames: try CloudKitRecordCodec.list(arguments["excludedZoneNames"], "excludedZoneNames")
          .map { try CloudKitRecordCodec.string($0, "excludedZoneNames") }
      )
    case "stop":
      await bridge.stop()
    case "addPendingRecordZoneChanges":
      try await bridge.addPendingRecordZoneChanges(
        CloudKitRecordCodec.decodePendingRecordZoneChanges(arguments["changes"])
      )
    case "removePendingRecordZoneChanges":
      try await bridge.removePendingRecordZoneChanges(
        CloudKitRecordCodec.decodePendingRecordZoneChanges(arguments["changes"])
      )
    case "addPendingDatabaseChanges":
      try await bridge.addPendingDatabaseChanges(
        CloudKitRecordCodec.decodePendingDatabaseChanges(arguments["changes"])
      )
    case "fetchChanges":
      try await bridge.fetchChanges()
    case "sendChanges":
      try await bridge.sendChanges()
    case "recordExists":
      return try await CloudKitAssetTransfers.recordExists(
        in: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"])
      )
    case "uploadAsset":
      try await CloudKitAssetTransfers.upload(
        to: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"]),
        recordType: CloudKitRecordCodec.string(arguments["recordType"], "recordType"),
        field: CloudKitRecordCodec.string(arguments["field"], "field"),
        source: URL(fileURLWithPath: CloudKitRecordCodec.string(arguments["sourcePath"], "sourcePath"))
      )
    case "downloadAsset":
      let transferId = arguments["transferId"] as? Int
      let channel = self.channel
      try await CloudKitAssetTransfers.download(
        from: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"]),
        field: CloudKitRecordCodec.string(arguments["field"], "field"),
        destination: URL(fileURLWithPath: CloudKitRecordCodec.string(arguments["destinationPath"], "destinationPath")),
        onProgress: { fraction in
          guard let transferId else { return }
          DispatchQueue.main.async {
            channel.invokeMethod("downloadProgress", arguments: ["transferId": transferId, "fraction": fraction])
          }
        }
      )
    default:
      return FlutterMethodNotImplemented
    }
    return nil
  }

  @available(iOS 17.0, macOS 14.0, *)
  @MainActor
  private var bridge: CloudKitSyncBridge {
    if let bridge = bridgeStorage as? CloudKitSyncBridge {
      return bridge
    }
    let channel = self.channel
    let bridge = CloudKitSyncBridge { method, arguments in
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
          channel.invokeMethod(method, arguments: arguments) { reply in
            if let error = reply as? FlutterError {
              continuation.resume(throwing: DartError(code: error.code, message: error.message))
            } else if (reply as? NSObject) === FlutterMethodNotImplemented {
              continuation.resume(throwing: DartError(code: "notImplemented", message: method))
            } else {
              continuation.resume(returning: Self.plainValue(reply))
            }
          }
        }
      }
    }
    bridgeStorage = bridge
    return bridge
  }

  @available(iOS 17.0, macOS 14.0, *)
  private func database(_ arguments: [String: Any]) throws -> CKDatabase {
    CKContainer(identifier: try CloudKitRecordCodec.string(arguments["containerId"], "containerId"))
      .privateCloudDatabase
  }

  /// Replaces Flutter typed data with `Data`, recursively, so the codec stays
  /// free of Flutter types. Outgoing `Data` needs no conversion: the standard
  /// codec writes it as bytes.
  private static func plainValue(_ value: Any?) -> Any? {
    switch value {
    case let typed as FlutterStandardTypedData:
      return typed.data
    case let list as [Any]:
      return list.map { plainValue($0) ?? NSNull() }
    case let map as [String: Any]:
      return map.mapValues { plainValue($0) ?? NSNull() }
    default:
      return value
    }
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    switch error {
    case let error as CloudKitSyncInvalidArgument:
      return FlutterError(code: "invalidArgument", message: error.message, details: nil)
    case let error as InvalidStateSerialization:
      return FlutterError(code: "invalidStateSerialization", message: "\(error.underlying)", details: nil)
    case let error as CloudKitSyncEngineNotRunning:
      return FlutterError(code: "engineNotRunning", message: error.reason, details: nil)
    case let error as CloudKitSyncMissingAsset:
      return FlutterError(code: "missingAsset", message: "The record has no asset in \(error.field).", details: nil)
    default:
      let nsError = error as NSError
      return FlutterError(
        code: "nativeError",
        message: nsError.localizedDescription,
        details: ["domain": nsError.domain, "code": nsError.code]
      )
    }
  }
}

private struct InvalidStateSerialization: Error {
  let underlying: Error
}

private struct DartError: Error, CustomStringConvertible {
  let code: String
  let message: String?

  var description: String { "Dart error \(code): \(message ?? "")" }
}
