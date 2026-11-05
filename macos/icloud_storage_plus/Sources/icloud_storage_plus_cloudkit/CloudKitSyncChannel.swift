#if os(iOS)
@preconcurrency import Flutter
#else
@preconcurrency import FlutterMacOS
#endif
import CloudKit
import Foundation

/// The Flutter side of the CloudKit sync bridge: its own method channel, kept
/// apart from document storage.
///
/// Flutter registers plugins, calls method channel handlers, and delivers
/// replies on the main thread, so the class is isolated to the main actor.
@MainActor
final class CloudKitSyncChannel: NSObject {
  static let channelName = "icloud_storage_plus/cloudkit_sync"

  private let channel: FlutterMethodChannel
  /// A `CloudKitSyncBridge`, created on first use. Typed as `AnyObject`
  /// because the bridge needs iOS 17 or macOS 14 and this class does not.
  private var bridgeStorage: AnyObject?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  nonisolated static func register(with registrar: FlutterPluginRegistrar) {
    MainActor.assumeIsolated {
      #if os(iOS)
      let messenger = registrar.messenger()
      #else
      let messenger = registrar.messenger
      #endif
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      let instance = CloudKitSyncChannel(channel: channel)
      channel.setMethodCallHandler { call, result in
        MainActor.assumeIsolated {
          instance.handle(call, result: result)
        }
      }
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
    Task {
      do {
        result(try await self.perform(call.method, arguments))
      } catch {
        let failure = CloudKitRecordCodec.encode(failure: error)
        result(FlutterError(code: failure.code, message: failure.message, details: failure.details))
      }
    }
  }

  @available(iOS 17.0, macOS 14.0, *)
  private func perform(_ method: String, _ arguments: [String: Any]) async throws -> Any? {
    switch method {
    case "start":
      let serialization: CKSyncEngine.State.Serialization?
      if let state = arguments["stateSerialization"] as? String {
        do {
          serialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: Data(state.utf8))
        } catch {
          throw CloudKitSyncInvalidStateSerialization(underlying: error)
        }
      } else {
        serialization = nil
      }
      await bridge.start(
        containerID: try CloudKitRecordCodec.string(arguments["containerId"], named: "containerId"),
        stateSerialization: serialization,
        excludedZoneNames: try CloudKitRecordCodec.list(arguments["excludedZoneNames"], named: "excludedZoneNames")
          .map { try CloudKitRecordCodec.string($0, named: "excludedZoneNames") }
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
    case "accountStatus":
      let container = CKContainer(
        identifier: try CloudKitRecordCodec.string(arguments["containerId"], named: "containerId")
      )
      return CloudKitRecordCodec.encode(try await container.accountStatus())
    case "recordExists":
      return try await CloudKitAssetTransfers.recordExists(
        in: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"])
      )
    case "uploadAsset":
      try await CloudKitAssetTransfers.upload(
        to: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"]),
        recordType: CloudKitRecordCodec.string(arguments["recordType"], named: "recordType"),
        field: CloudKitRecordCodec.string(arguments["field"], named: "field"),
        source: URL(fileURLWithPath: CloudKitRecordCodec.string(arguments["sourcePath"], named: "sourcePath"))
      )
    case "downloadAsset":
      let transferId = arguments["transferId"] as? Int
      try await CloudKitAssetTransfers.download(
        from: database(arguments),
        id: CloudKitRecordCodec.decodeRecordID(arguments["id"]),
        field: CloudKitRecordCodec.string(arguments["field"], named: "field"),
        destination: URL(
          fileURLWithPath: CloudKitRecordCodec.string(arguments["destinationPath"], named: "destinationPath")
        ),
        onProgress: { fraction in
          guard let transferId else { return }
          DispatchQueue.main.async {
            self.channel.invokeMethod("downloadProgress", arguments: ["transferId": transferId, "fraction": fraction])
          }
        }
      )
    default:
      return FlutterMethodNotImplemented
    }
    return nil
  }

  @available(iOS 17.0, macOS 14.0, *)
  private var bridge: CloudKitSyncBridge {
    if let bridge = bridgeStorage as? CloudKitSyncBridge {
      return bridge
    }
    let bridge = CloudKitSyncBridge { @MainActor method, arguments in
      try await withCheckedThrowingContinuation { continuation in
        self.channel.invokeMethod(method, arguments: arguments) { reply in
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
    bridgeStorage = bridge
    return bridge
  }

  @available(iOS 17.0, macOS 14.0, *)
  private func database(_ arguments: [String: Any]) throws -> CKDatabase {
    CKContainer(identifier: try CloudKitRecordCodec.string(arguments["containerId"], named: "containerId"))
      .privateCloudDatabase
  }

  /// Replaces Flutter typed data with `Data`, recursively, so the codec stays
  /// free of Flutter types. Outgoing `Data` needs no conversion: the standard
  /// codec writes it as bytes.
  private nonisolated static func plainValue(_ value: Any?) -> Any? {
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
}

private struct DartError: Error, CustomStringConvertible {
  let code: String
  let message: String?

  var description: String { "Dart error \(code): \(message ?? "")" }
}
