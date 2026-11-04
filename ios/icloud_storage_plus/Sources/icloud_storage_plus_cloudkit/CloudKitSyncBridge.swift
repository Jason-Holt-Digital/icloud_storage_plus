import CloudKit
import Foundation

/// Calls a Dart method on the CloudKit sync channel and returns its reply.
/// Throws when Dart replies with an error.
typealias CloudKitSyncDartCall = @Sendable (_ method: String, _ arguments: [String: Any]) async throws -> Any?

/// The engine stopped, or was never started.
struct CloudKitSyncEngineNotRunning: Error {
  let reason: String?
}

/// Wraps one `CKSyncEngine` for the private database and forwards its
/// delegate calls to Dart. It makes no sync decisions.
@available(iOS 17.0, macOS 14.0, *)
actor CloudKitSyncBridge: CKSyncEngineDelegate {
  /// CloudKit's limit on saves plus deletes in one request.
  static let maxChangesPerBatch = 250

  private let callDart: CloudKitSyncDartCall
  private var engine: CKSyncEngine?
  private var excludedZoneIDs: [CKRecordZone.ID] = []
  private var stopReason: String?

  init(callDart: @escaping CloudKitSyncDartCall) {
    self.callDart = callDart
  }

  /// Replaces any running engine with a new one for `containerID`.
  func start(containerID: String, stateSerialization: CKSyncEngine.State.Serialization?, excludedZoneNames: [String]) async {
    // Install the replacement before the only suspension point, so a start or
    // stop that runs while the old engine cancels sees the new engine.
    let previousEngine = engine
    excludedZoneIDs = excludedZoneNames.map { CKRecordZone.ID(zoneName: $0) }
    stopReason = nil
    engine = CKSyncEngine(
      CKSyncEngine.Configuration(
        database: CKContainer(identifier: containerID).privateCloudDatabase,
        stateSerialization: stateSerialization,
        delegate: self
      )
    )
    await previousEngine?.cancelOperations()
  }

  func stop() async {
    await stop(engine, reason: "The engine was stopped.")
  }

  func addPendingRecordZoneChanges(_ changes: [CKSyncEngine.PendingRecordZoneChange]) throws {
    try runningEngine().state.add(pendingRecordZoneChanges: changes)
  }

  func removePendingRecordZoneChanges(_ changes: [CKSyncEngine.PendingRecordZoneChange]) throws {
    try runningEngine().state.remove(pendingRecordZoneChanges: changes)
  }

  func addPendingDatabaseChanges(_ changes: [CKSyncEngine.PendingDatabaseChange]) throws {
    try runningEngine().state.add(pendingDatabaseChanges: changes)
  }

  func fetchChanges() async throws {
    let engine = try runningEngine()
    try await engine.fetchChanges(
      CKSyncEngine.FetchChangesOptions(scope: Self.scope(.all, excluding: excludedZoneIDs))
    )
  }

  func sendChanges() async throws {
    try await runningEngine().sendChanges()
  }

  private func runningEngine() throws -> CKSyncEngine {
    guard let engine else { throw CloudKitSyncEngineNotRunning(reason: stopReason) }
    return engine
  }

  /// Drops `stoppedEngine` if it is still the current engine, so no later
  /// event from it reaches Dart. Dart's next call fails with `reason`.
  private func stop(_ stoppedEngine: CKSyncEngine?, reason: String) async {
    guard let stoppedEngine, stoppedEngine === engine else { return }
    engine = nil
    stopReason = reason
    await stoppedEngine.cancelOperations()
  }

  /// Narrows a fetch `scope` so it never includes `excludedZoneIDs`.
  static func scope(
    _ scope: CKSyncEngine.FetchChangesOptions.Scope,
    excluding excludedZoneIDs: [CKRecordZone.ID]
  ) -> CKSyncEngine.FetchChangesOptions.Scope {
    guard !excludedZoneIDs.isEmpty else { return scope }
    switch scope {
    case .all:
      return .allExcluding(excludedZoneIDs)
    case .allExcluding(let zoneIDs):
      return .allExcluding(zoneIDs + excludedZoneIDs.filter { !zoneIDs.contains($0) })
    case .zoneIDs(let zoneIDs):
      return .zoneIDs(zoneIDs.filter { !excludedZoneIDs.contains($0) })
    @unknown default:
      return scope
    }
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard syncEngine === engine else { return }
    do {
      guard let payload = try CloudKitRecordCodec.encode(event) else { return }
      _ = try await callDart("handleEvent", payload)
    } catch {
      // CKSyncEngine treats an event as handled once this method returns, and
      // its next stateUpdate would move past it. Dropping the engine keeps the
      // app's saved state at the last event it handled; the next start
      // delivers the unhandled changes again.
      await stop(syncEngine, reason: "An event was not handled: \(error)")
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard syncEngine === engine else { return nil }
    // A batch must stay inside the context's scope, or the send fails with
    // invalidArguments.
    let scope = context.options.scope
    let pendingChanges = syncEngine.state.pendingRecordZoneChanges
      .filter { scope.contains($0) }
      .prefix(Self.maxChangesPerBatch)
      .compactMap { CloudKitRecordCodec.encode($0) }
    guard !pendingChanges.isEmpty else { return nil }

    // A failed or empty reply ends this send. The changes stay pending, and
    // the engine asks again on its next send. Dart has already reported its
    // own failure.
    guard
      let reply = try? await callDart("nextRecordZoneChangeBatch", ["pendingChanges": pendingChanges]),
      !(reply is NSNull)
    else { return nil }
    let batch: (recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID])
    do {
      batch = try CloudKitRecordCodec.decodeBatch(reply)
    } catch {
      // Dart cannot see this failure, and every later send would fail the
      // same way, so stop and give the next Dart call the reason.
      await stop(syncEngine, reason: "A record batch could not be read: \(error)")
      return nil
    }
    let recordsByID = Dictionary(
      batch.recordsToSave.map { ($0.recordID, $0) },
      uniquingKeysWith: { _, last in last }
    )
    let changes: [CKSyncEngine.PendingRecordZoneChange] =
      batch.recordsToSave.map { .saveRecord($0.recordID) } + batch.recordIDsToDelete.map { .deleteRecord($0) }
    guard !changes.isEmpty else { return nil }
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordsByID[$0] }
  }

  func nextFetchChangesOptions(
    _ context: CKSyncEngine.FetchChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.FetchChangesOptions {
    var options = context.options
    options.scope = Self.scope(options.scope, excluding: excludedZoneIDs)
    return options
  }
}
