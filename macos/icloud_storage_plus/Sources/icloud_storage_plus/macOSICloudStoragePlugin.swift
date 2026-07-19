import Cocoa
import FlutterMacOS

public class ICloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  private var eventChannelRegistrations: [
    String: EventChannelRegistration
  ] = [:]
  private var retiringEventChannelRegistrations: [
    String: EventChannelRegistration
  ] = [:]
  private var progressByEventChannel: [String: Double] = [:]
  private let streamStateQueue = DispatchQueue(
    label: "icloud_storage_plus.stream_state"
  )
  let querySearchScopes = iCloudMetadataQuerySearchScopes
  private var metadataQuerySessions: [
    MetadataQuerySession.ID: MetadataQuerySession
  ] = [:]
  private let metadataQuerySessionsQueue = DispatchQueue(
    label: "icloud_storage_plus.metadata_query_sessions"
  )
  private let metadataQueryOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "icloud_storage_plus.metadata_query"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    return queue
  }()
  private var documentChangeRegistrations: [
    String: DocumentChangeRegistration
  ] = [:]
  private let documentChangeRegistrationsQueue = DispatchQueue(
    label: "icloud_storage_plus.document_change_registrations"
  )
  private let ubiquityContainerResolver: UbiquityContainerResolver

  init(
    ubiquityContainerResolver: UbiquityContainerResolver = .live
  ) {
    self.ubiquityContainerResolver = ubiquityContainerResolver
    super.init()
  }

  func coordinatedReplaceWriter(
    for url: URL
  ) -> CoordinatedReplaceWriter {
    let standardizedPath = url.standardizedFileURL.path
    let initialRegistrations = documentChangeRegistrations(
      for: standardizedPath
    )
    return CoordinatedReplaceWriter.makeLive(
      filePresenter: initialRegistrations.first?.presenter,
      afterSuccessfulReplace: { [self, initialRegistrations] resultingURL in
        let currentRegistrations = documentChangeRegistrations(
          for: standardizedPath
        )
        var seenRegistrations = Set<ObjectIdentifier>()
        for registration in initialRegistrations + currentRegistrations
        where seenRegistrations.insert(ObjectIdentifier(registration)).inserted {
          registration.presenter.recordSuccessfulPassiveWrite(at: resultingURL)
        }
      }
    )
  }

  private func documentChangeRegistrations(
    for standardizedPath: String
  ) -> [DocumentChangeRegistration] {
    documentChangeRegistrationsQueue.sync {
      documentChangeRegistrations.values.filter {
        $0.standardizedPath == standardizedPath
      }
    }
  }

  deinit {
    let sessions = metadataQuerySessionsQueue.sync {
      Array(metadataQuerySessions.values)
    }
    for session in sessions {
      session.cancel()
    }
    let registrations = documentChangeRegistrationsQueue.sync {
      Array(documentChangeRegistrations.values)
    }
    for registration in registrations {
      registration.cancel()
    }
  }

  /// Registers the plugin with the Flutter registrar.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "icloud_storage_plus", binaryMessenger: registrar.messenger)
    let instance = ICloudStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.messenger = registrar.messenger
  }

  /// Routes Flutter method calls to native handlers.
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "icloudAvailable":
      icloudAvailable(result)
    case "gather":
      gather(call, result)
    case "watchDocumentChanges":
      watchDocumentChanges(call, result)
    case "uploadFile":
      uploadFile(call, result)
    case "downloadFile":
      downloadFile(call, result)
    case "readInPlace":
      readInPlace(call, result)
    case "readInPlaceBytes":
      readInPlaceBytes(call, result)
    case "writeInPlace":
      writeInPlace(call, result)
    case "writeInPlaceBytes":
      writeInPlaceBytes(call, result)
    case "delete":
      delete(call, result)
    case "move":
      move(call, result)
    case "copy":
      copy(call, result)
    case "createEventChannel":
      createEventChannel(call, result)
    case "getContainerPath":
      getContainerPath(call, result)
    case "documentExists":
      documentExists(call, result)
    case "getItemMetadata":
      getItemMetadata(call, result)
    case "listContents":
      listContents(call, result)
    case "enumerateUnresolvedConflictVersions":
      enumerateUnresolvedConflictVersions(call, result)
    case "copyConflictVersion":
      copyConflictVersion(call, result)
    case "markConflictResolved":
      markConflictResolved(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  /// Returns whether iCloud is available for the current user.
  private func icloudAvailable(_ result: @escaping FlutterResult) {
    let status = FileManager.default.ubiquityIdentityToken != nil
    result(status)
  }

  private func resolveContainerURL(
    containerId: String,
    operation: String,
    relativePath: String? = nil,
    result: @escaping FlutterResult,
    onFailure: ((FlutterError) -> Bool)? = nil,
    onResolved: @escaping (URL) -> Void
  ) {
    Task { @MainActor [self] in
      guard let containerURL = await ubiquityContainerResolver.resolve(
        containerId: containerId
      ) else {
        let error = containerAccessError(
          operation: operation,
          relativePath: relativePath
        )
        let deliveredToStream = onFailure?(error) ?? false
        result(deliveredToStream ? nil : error)
        return
      }

      onResolved(containerURL)
    }
  }

  /// Returns the filesystem path for the iCloud container.
  private func getContainerPath(_ call: FlutterMethodCall, _ result: @escaping FlutterResult){
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String
    else {
      result(argumentError(operation: "getContainerPath"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "getContainerPath",
      result: result
    ) { containerURL in
      result(containerURL.path)
    }
  }
  
  /// Lists all items in the container using NSMetadataQuery.
  private func gather(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError(operation: "gather"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "gather",
      result: result,
      onFailure: { [weak self] _ in
        if !eventChannelName.isEmpty {
          self?.removeStreamHandler(eventChannelName)
        }
        return false
      }
    ) { [self] containerURL in
      startGather(
        containerURL: containerURL,
        eventChannelName: eventChannelName,
        result: result
      )
    }
  }

  private func startGather(
    containerURL: URL,
    eventChannelName: String,
    result: @escaping FlutterResult
  ) {
    DebugHelper.log("containerURL: \(containerURL.path)")

    let streamHandler = eventChannelName.isEmpty
      ? nil
      : registeredStreamHandler(for: eventChannelName)
    let activeEventChannelName = streamHandler == nil ? "" : eventChannelName

    let query = NSMetadataQuery.init()
    query.operationQueue = metadataQueryOperationQueue
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    let session = makeMetadataQuerySession(query: query)
    let lifecycle = GatherSessionLifecycle()
    addGatherFilesObservers(
      session: session,
      lifecycle: lifecycle,
      containerURL: containerURL,
      eventChannelName: activeEventChannelName,
      result: result
    )

    if let streamHandler {
      streamHandler.onCancelHandler = { [weak self, weak session] in
        if lifecycle.updatesDidCancel() {
          session?.cancel()
        }
        self?.removeStreamHandler(eventChannelName)
      }
    }
    session.start()
  }

  /// Watches the existing ICloudDocument presenter's document-change events.
  private func watchDocumentChanges(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String,
          !eventChannelName.isEmpty
    else {
      result(argumentError(operation: "watchDocumentChanges"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "watchDocumentChanges",
      relativePath: relativePath,
      result: result,
      onFailure: { [weak self] _ in
        self?.removeStreamHandler(eventChannelName)
        return false
      }
    ) { [self] containerURL in
      startDocumentChangeObservation(
        containerURL: containerURL,
        relativePath: relativePath,
        eventChannelName: eventChannelName,
        result: result
      )
    }
  }

  private func startDocumentChangeObservation(
    containerURL: URL,
    relativePath: String,
    eventChannelName: String,
    result: @escaping FlutterResult
  ) {
    guard let streamHandler = registeredStreamHandler(for: eventChannelName)
    else {
      result(missingEventHandlerError(
        eventChannelName: eventChannelName,
        operation: "watchDocumentChanges",
        relativePath: relativePath
      ))
      return
    }

    let documentURL = containerURL.appendingPathComponent(relativePath)
    let document = ICloudDocument(fileURL: documentURL)
    let observation = DocumentChangeObservation(
      relativePath: relativePath,
      onStart: { [weak document] in
        guard let document else { return }
        try document.startPassiveChangePresentation()
      },
      onCancel: { [weak document] in
        document?.stopPassiveChangePresentation()
      },
      emit: { payload in
        DispatchQueue.main.async {
          streamHandler.setEvent(payload)
        }
      }
    )
    document.configurePassiveChangeObservation(observation)
    let registration = DocumentChangeRegistration(
      documentURL: documentURL,
      document: document,
      observation: observation
    )
    setDocumentChangeRegistration(registration, for: eventChannelName)
    streamHandler.onCancelHandler = { [weak self, weak registration] in
      guard let self, let registration else { return }

      registration.cancel()
      if self.removeDocumentChangeRegistration(
        eventChannelName,
        matching: registration
      ) {
        self.removeStreamHandler(eventChannelName)
      }
    }

    // `observation.start()` performs synchronous `NSFileCoordinator`
    // coordination and an attribute lookup. `resolveContainerURL` delivers
    // here on the main actor, so run the coordination on a background queue
    // to avoid blocking the main thread while File Provider/iCloud is slow.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try observation.start()
        DispatchQueue.main.async { result(nil) }
      } catch {
        registration.cancel()
        _ = self.removeDocumentChangeRegistration(
          eventChannelName,
          matching: registration
        )
        self.removeStreamHandler(eventChannelName)
        let flutterError = self.nativeCodeError(
          error,
          operation: "watchDocumentChanges",
          relativePath: relativePath
        )
        DispatchQueue.main.async { result(flutterError) }
      }
    }
  }
  
  /// Adds observers for metadata gather and update notifications.
  private func addGatherFilesObservers(
    session: MetadataQuerySession,
    lifecycle: GatherSessionLifecycle,
    containerURL: URL,
    eventChannelName: String,
    result: @escaping FlutterResult
  ) {
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [weak self] session, query, _ in
      guard let self else { return }
      query.disableUpdates()
      defer {
        if !session.isCancelled {
          query.enableUpdates()
        }
      }
      let results = query.results.compactMap { $0 as? NSMetadataItem }
      if eventChannelName.isEmpty || lifecycle.initialGatherDidComplete() {
        session.cancel()
      }

      let files = mapFileAttributes(items: results, containerURL: containerURL)
      DispatchQueue.main.async {
        result(files)
      }
    }
    
    if !eventChannelName.isEmpty {
      session.addObserver(
        name: NSNotification.Name.NSMetadataQueryDidUpdate
      ) { [weak self] session, query, _ in
        guard let self else { return }
        guard hasStreamHandler(named: eventChannelName) else {
          return
        }

        query.disableUpdates()
        defer {
          if !session.isCancelled {
            query.enableUpdates()
          }
        }
        let results = query.results.compactMap { $0 as? NSMetadataItem }
        let files = mapFileAttributes(items: results, containerURL: containerURL)
        DispatchQueue.main.async {
          guard let streamHandler = self.registeredStreamHandler(
            for: eventChannelName
          ) else {
            return
          }
          streamHandler.setEvent(files)
        }
      }
    }
  }
  
  /// Maps query results into metadata dictionaries.
  private func mapFileAttributes(items: [NSMetadataItem], containerURL: URL) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    let containerPath = containerURL.standardizedFileURL.path
    for item in items {
      guard let map = mapMetadataItem(item, containerPath: containerPath) else {
        continue
      }
      fileMaps.append(map)
    }
    return fileMaps
  }

  /// Map an NSMetadataItem into a Flutter-friendly metadata dictionary.
  /// Includes directories and sets `isDirectory` for caller interpretation.
  private func mapMetadataItem(_ item: NSMetadataItem, containerPath: String) -> [String: Any?]? {
    guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
      return nil
    }

    return [
      "relativePath": relativePath(for: fileURL, containerPath: containerPath),
      "isDirectory": fileURL.hasDirectoryPath,
      "sizeInBytes": item.value(forAttribute: NSMetadataItemFSSizeKey),
      "creationDate": (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date)?.timeIntervalSince1970,
      "contentChangeDate": (item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970,
      "hasUnresolvedConflicts": (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) ?? false,
      "downloadStatus": normalizeDownloadStatus(
        item.value(
          forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
        ) as? String
      ),
      "isDownloading": (item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool) ?? false,
      "isUploaded": (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false,
      "isUploading": (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) ?? false,
    ]
  }

  /// Map URL resource values into a Flutter-friendly metadata dictionary.
  private func mapResourceValues(
    fileURL: URL,
    values: URLResourceValues,
    containerPath: String
  ) -> [String: Any?] {
    return [
      "relativePath": relativePath(for: fileURL, containerPath: containerPath),
      "isDirectory": values.isDirectory ?? false,
      "sizeInBytes": values.fileSize,
      "creationDate": values.creationDate?.timeIntervalSince1970,
      "contentChangeDate": values.contentModificationDate?.timeIntervalSince1970,
      "hasUnresolvedConflicts": values.ubiquitousItemHasUnresolvedConflicts ?? false,
      "downloadStatus": normalizeDownloadStatus(
        values.ubiquitousItemDownloadingStatus
      ),
      "isDownloading": values.ubiquitousItemIsDownloading ?? false,
      "isUploaded": values.ubiquitousItemIsUploaded ?? false,
      "isUploading": values.ubiquitousItemIsUploading ?? false,
    ]
  }

  /// Computes the container-relative path for a URL.
  private func relativePath(for fileURL: URL, containerPath: String) -> String {
    let filePath = fileURL.standardizedFileURL.path
    let normalizedContainerPath = containerPath.hasSuffix("/")
      ? containerPath
      : containerPath + "/"
    guard filePath == containerPath || filePath.hasPrefix(normalizedContainerPath) else {
      return fileURL.lastPathComponent
    }
    let prefixLength = filePath == containerPath
      ? containerPath.count
      : normalizedContainerPath.count
    var relative = String(filePath.dropFirst(prefixLength))
    if relative.hasPrefix("/") {
      relative.removeFirst()
    }
    return relative
  }
  
  private func prepareWriteEntrypointURL(
    containerId: String,
    relativePath: String
  ) async throws -> URL {
    try await WriteEntrypointPreflight.live.prepare(
      containerId: containerId,
      relativePath: relativePath
    )
  }

  private func mapWriteEntrypointPreflightError(
    _ error: Error,
    operation: String,
    relativePath: String
  ) -> FlutterError {
    if WriteEntrypointPreflight.isContainerUnavailableError(error) {
      return containerAccessError(
        operation: operation,
        relativePath: relativePath
      )
    }

    return nativeCodeError(
      error,
      operation: operation,
      relativePath: relativePath,
      pathKind: "containerParentDirectory"
    )
  }

  private func mapNativeWriteError(
    _ error: Error,
    operation: String,
    relativePath: String,
    destinationURL: URL
  ) -> FlutterError {
    let nsError = error as NSError
    return mapFileNotFoundError(
      error,
      operation: operation,
      relativePath: relativePath,
      pathKind: nativeWritePathKind(
        for: nsError,
        destinationURL: destinationURL
      )
    ) ?? nativeCodeError(
      error,
      operation: operation,
      relativePath: relativePath,
      pathKind: nativeWritePathKind(
        for: nsError,
        destinationURL: destinationURL
      )
    )
  }

  private func nativeWritePathKind(
    for nativeError: NSError,
    destinationURL: URL
  ) -> String {
    guard let nativePath = nativeError.userInfo[NSFilePathErrorKey] as? String
    else {
      return "containerRelative"
    }

    let standardizedNativePath = URL(fileURLWithPath: nativePath)
      .standardizedFileURL
      .path
    let standardizedDestinationPath = destinationURL
      .standardizedFileURL
      .path
    if standardizedNativePath == standardizedDestinationPath {
      return "destination"
    }

    let temporaryPath = FileManager.default.temporaryDirectory
      .standardizedFileURL
      .path
    let normalizedTemporaryPath = temporaryPath.hasSuffix("/")
      ? temporaryPath
      : temporaryPath + "/"
    if standardizedNativePath.hasPrefix(normalizedTemporaryPath) {
      return "temporaryReplacement"
    }

    return "nativeFilePath"
  }

  private func isFileContentWriteOperation(_ operation: String) -> Bool {
    operation == "uploadFile"
      || operation == "writeInPlace"
      || operation == "writeInPlaceBytes"
  }

  /// Copies a local file into the iCloud container (copy-in).
  /// iCloud uploads the container file automatically in the background.
  private func uploadFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let relativePath = args["relativePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError(operation: "uploadFile"))
      return
    }
    let localFileURL = URL(fileURLWithPath: localFilePath)

    Task { @MainActor [self] in
      let cloudFileURL: URL
      do {
        cloudFileURL = try await prepareWriteEntrypointURL(
          containerId: containerId,
          relativePath: relativePath
        )
      } catch {
        let mapped = mapWriteEntrypointPreflightError(
          error,
          operation: "uploadFile",
          relativePath: relativePath
        )
        let deliveredToStream = failProgressStream(
          eventChannelName: eventChannelName,
          error: mapped
        )
        result(deliveredToStream ? nil : mapped)
        return
      }

      DebugHelper.log("containerURL: \(cloudFileURL.deletingLastPathComponent().path)")
      do {
        // Request proactive materialization (request, not a deadline)
        // for a not-yet-`.current` upload destination.
        do {
          _ = try UbiquitousItemMaterializer.live
            .requestMaterializationIfNeeded(at: cloudFileURL)
        } catch {
          DebugHelper.log(
            "uploadFile materialization request failed: "
              + "\(error.localizedDescription)"
          )
        }

        try await PerPathMutationLane.shared.withLane(for: cloudFileURL) {
          try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            self.writeDocument(at: cloudFileURL, sourceURL: localFileURL) {
              error in
              if let error {
                cont.resume(throwing: error)
              } else {
                cont.resume()
              }
            }
          }
        }
        // Set up progress monitoring if needed
        if !eventChannelName.isEmpty {
          self.setupUploadProgressMonitoring(
            cloudFileURL: cloudFileURL,
            relativePath: relativePath,
            eventChannelName: eventChannelName
          )
        }
        result(nil)
      } catch {
        let mapped = self.nativeCodeError(
          error,
          operation: "uploadFile",
          relativePath: relativePath
        )
        let deliveredToStream = self.failProgressStream(
          eventChannelName: eventChannelName,
          error: mapped
        )
        result(deliveredToStream ? nil : mapped)
      }
    }
  }
  
  /// Starts a metadata query to report upload progress.
  private func setupUploadProgressMonitoring(
    cloudFileURL: URL,
    relativePath: String,
    eventChannelName: String
  ) {
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    let session = makeMetadataQuerySession(query: query)

    guard let uploadStreamHandler = registeredStreamHandler(
      for: eventChannelName
    ) else {
      session.cancel()
      return
    }
    emitProgress(10.0, eventChannelName: eventChannelName)
    uploadStreamHandler.onCancelHandler = { [weak self, weak session] in
      session?.cancel()
      self?.removeStreamHandler(eventChannelName)
    }
    addUploadObservers(
      session: session,
      relativePath: relativePath,
      eventChannelName: eventChannelName
    )

    session.start()
  }
  
  /// Adds observers for upload progress updates.
  private func addUploadObservers(
    session: MetadataQuerySession,
    relativePath: String,
    eventChannelName: String
  ) {
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [weak self] session, query, _ in
      guard let self else { return }
      onUploadQueryNotification(
        session: session,
        query: query,
        relativePath: relativePath,
        eventChannelName: eventChannelName
      )
    }
    
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [weak self] session, query, _ in
      guard let self else { return }
      onUploadQueryNotification(
        session: session,
        query: query,
        relativePath: relativePath,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits upload progress updates to the event channel.
  private func onUploadQueryNotification(
    session: MetadataQuerySession,
    query: NSMetadataQuery,
    relativePath: String,
    eventChannelName: String
  ) {
    if session.isCancelled || !query.isStarted {
      return
    }

    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(
      forKeys: [.ubiquitousItemUploadingErrorKey]
    ) else { return }
    guard hasStreamHandler(named: eventChannelName) else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      guard let streamHandler = registeredStreamHandler(
        for: eventChannelName
      ) else {
        return
      }
      streamHandler.finish(with: [
        nativeCodeError(
          error,
          operation: "uploadFile",
          relativePath: relativePath
        ),
        FlutterEndOfEventStream,
      ])
      session.cancel()
      removeStreamHandler(eventChannelName)
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      emitProgress(progress, eventChannelName: eventChannelName)
      if (progress >= 100) {
        guard let streamHandler = registeredStreamHandler(
          for: eventChannelName
        ) else {
          return
        }
        streamHandler.finish(with: [FlutterEndOfEventStream])
        session.cancel()
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  /// Downloads an iCloud item if needed, then copies it out to a local path.
  private func downloadFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError(operation: "downloadFile"))
      return
    }
    
    resolveContainerURL(
      containerId: containerId,
      operation: "downloadFile",
      relativePath: relativePath,
      result: result,
      onFailure: { [weak self] error in
        self?.failProgressStream(
          eventChannelName: eventChannelName,
          error: error
        ) ?? false
      }
    ) { [self] containerURL in
      DebugHelper.log("containerURL: \(containerURL.path)")

      let cloudFileURL = containerURL.appendingPathComponent(relativePath)
      let localFileURL = URL(fileURLWithPath: localFilePath)
      do {
        try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
      } catch {
        let mapped = mapFileNotFoundError(
          error,
          operation: "downloadFile",
          relativePath: relativePath
        ) ?? nativeCodeError(
          error,
          operation: "downloadFile",
          relativePath: relativePath
        )
        let deliveredToStream = failProgressStream(
          eventChannelName: eventChannelName,
          error: mapped
        )
        result(deliveredToStream ? nil : mapped)
        return
      }

      let completionGate = CompletionGate()
      let completeOnce: (Any?) -> Void = { value in
        guard completionGate.tryComplete() else {
          return
        }
        result(value)
      }

      let downloadSession: MetadataQuerySession? = eventChannelName.isEmpty
        ? nil
        : {
            let query = NSMetadataQuery()
            query.operationQueue = .main
            query.searchScopes = querySearchScopes
            query.predicate = NSPredicate(
              format: "%K == %@",
              NSMetadataItemPathKey,
              cloudFileURL.path
            )
            return makeMetadataQuerySession(query: query)
          }()

      let downloadStreamHandler = registeredStreamHandler(for: eventChannelName)
      if let downloadSession {
        downloadStreamHandler?.onCancelHandler = {
          [weak self, weak downloadSession] in
          guard let self else { return }
          // Cancelling the progress stream stops progress monitoring only.
          // The copy-out is not cancellable, so let readDocumentAt drive the
          // final result instead of reporting a cancellation while the file
          // is still being written to localFileURL.
          downloadSession?.cancel()
          self.removeStreamHandler(eventChannelName)
        }
      }

      if let downloadSession {
        addDownloadObservers(
          session: downloadSession,
          eventChannelName: eventChannelName
        )
        downloadSession.start()
      }
      if downloadStreamHandler != nil {
        emitProgress(10.0, eventChannelName: eventChannelName)
      }

      readDocumentAt(url: cloudFileURL, destinationURL: localFileURL) {
        [self] error in
        if completionGate.isCompleted {
          return
        }
        if let error = error {
          let mapped = mapFileNotFoundError(
            error,
            operation: "downloadFile",
            relativePath: relativePath
          ) ?? nativeCodeError(
            error,
            operation: "downloadFile",
            relativePath: relativePath
          )
          let deliveredToStream = downloadStreamHandler?.finish(with: [
            mapped,
            FlutterEndOfEventStream,
          ]) ?? false
          downloadSession?.cancel()
          removeStreamHandler(eventChannelName)
          completeOnce(deliveredToStream ? nil : mapped)
          return
        }

        emitProgress(100.0, eventChannelName: eventChannelName)
        downloadStreamHandler?.finish(with: [FlutterEndOfEventStream])
        downloadSession?.cancel()
        removeStreamHandler(eventChannelName)
        completeOnce(nil)
      }
    }
  }

  /// Read a file in place from the iCloud container using coordinated access.
  private func readInPlace(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "readInPlace"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "readInPlace",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)

      Task { @MainActor [self] in
        self.readInPlaceDocument(at: fileURL) { [self] contents, error in
          if let error = error {
            let mapped = self.mapFileNotFoundError(
              error,
              operation: "readInPlace",
              relativePath: relativePath
            ) ?? self.nativeCodeError(
              error,
              operation: "readInPlace",
              relativePath: relativePath
            )
            result(mapped)
            return
          }

          result(contents)
        }
      }
    }
  }

  /// Write a file in place inside the iCloud container using coordinated access.
  private func writeInPlace(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let contents = args["contents"] as? String
    else {
      result(argumentError(operation: "writeInPlace"))
      return
    }

    Task { @MainActor [self] in
      let fileURL: URL
      do {
        fileURL = try await prepareWriteEntrypointURL(
          containerId: containerId,
          relativePath: relativePath
        )
      } catch {
        result(mapWriteEntrypointPreflightError(
          error,
          operation: "writeInPlace",
          relativePath: relativePath
        ))
        return
      }

      do {
        // Request proactive materialization for a not-yet-`.current`
        // item (request, not a deadline). A failed request is logged
        // and never blocks the write — normal lifecycle states are not
        // errors (VAL-MUT-030/031/032/033).
        do {
          _ = try UbiquitousItemMaterializer.live
            .requestMaterializationIfNeeded(at: fileURL)
        } catch {
          DebugHelper.log(
            "writeInPlace materialization request failed: "
              + "\(error.localizedDescription)"
          )
        }

        try await PerPathMutationLane.shared.withLane(for: fileURL) {
          try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            self.writeInPlaceDocument(at: fileURL, contents: contents) {
              error in
              if let error {
                cont.resume(throwing: error)
              } else {
                cont.resume()
              }
            }
          }
        }
        result(nil)
      } catch {
        result(mapNativeWriteError(
          error,
          operation: "writeInPlace",
          relativePath: relativePath,
          destinationURL: fileURL
        ))
      }
    }
  }

  /// Read a file in place as bytes from the iCloud container using coordinated access.
  private func readInPlaceBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "readInPlaceBytes"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "readInPlaceBytes",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)

      Task { @MainActor [self] in
        self.readInPlaceBinaryDocument(at: fileURL) { [self] contents, error in
          if let error = error {
            let mapped = self.mapFileNotFoundError(
              error,
              operation: "readInPlaceBytes",
              relativePath: relativePath
            ) ?? self.nativeCodeError(
              error,
              operation: "readInPlaceBytes",
              relativePath: relativePath
            )
            result(mapped)
            return
          }

          if let contents {
            result(FlutterStandardTypedData(bytes: contents))
          } else {
            result(nil)
          }
        }
      }
    }
  }

  /// Write a file in place as bytes inside the iCloud container using coordinated access.
  private func writeInPlaceBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let contents = args["contents"] as? FlutterStandardTypedData
    else {
      result(argumentError(operation: "writeInPlaceBytes"))
      return
    }

    Task { @MainActor [self] in
      let fileURL: URL
      do {
        fileURL = try await prepareWriteEntrypointURL(
          containerId: containerId,
          relativePath: relativePath
        )
      } catch {
        result(mapWriteEntrypointPreflightError(
          error,
          operation: "writeInPlaceBytes",
          relativePath: relativePath
        ))
        return
      }

      do {
        // Request proactive materialization (request, not a deadline).
        // A failed request is logged and never blocks the write
        // (VAL-MUT-030/031/032/033).
        do {
          _ = try UbiquitousItemMaterializer.live
            .requestMaterializationIfNeeded(at: fileURL)
        } catch {
          DebugHelper.log(
            "writeInPlaceBytes materialization request failed: "
              + "\(error.localizedDescription)"
          )
        }

        try await PerPathMutationLane.shared.withLane(for: fileURL) {
          try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            self.writeInPlaceBinaryDocument(
              at: fileURL,
              contents: contents.data
            ) { error in
              if let error {
                cont.resume(throwing: error)
              } else {
                cont.resume()
              }
            }
          }
        }
        result(nil)
      } catch {
        result(mapNativeWriteError(
          error,
          operation: "writeInPlaceBytes",
          relativePath: relativePath,
          destinationURL: fileURL
        ))
      }
    }
  }
  
  /// Adds observers for download progress updates.
  private func addDownloadObservers(
    session: MetadataQuerySession,
    eventChannelName: String
  ) {
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [weak self] session, query, _ in
      guard let self else { return }
      emitDownloadProgress(
        session: session,
        query: query,
        eventChannelName: eventChannelName
      )
    }
    
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [weak self] session, query, _ in
      guard let self else { return }
      emitDownloadProgress(
        session: session,
        query: query,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits download progress updates.
  private func emitDownloadProgress(
    session: MetadataQuerySession,
    query: NSMetadataQuery,
    eventChannelName: String
  ) {
    if session.isCancelled || !query.isStarted {
      return
    }
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      emitProgress(progress, eventChannelName: eventChannelName)
    }
  }

  
  /// Check if an item exists without downloading.
  private func documentExists(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "documentExists"))
      return
    }
    
    resolveContainerURL(
      containerId: containerId,
      operation: "documentExists",
      relativePath: relativePath,
      result: result
    ) { containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)
      result(FileManager.default.fileExists(atPath: fileURL.path))
    }
  }

  /// Get typed metadata for a known path without downloading content.
  /// Returns normalized download status strings and `nil` for missing items.
  private func getItemMetadata(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "getItemMetadata"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "getItemMetadata",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        result(nil)
        return
      }

      do {
        let values = try fileURL.resourceValues(forKeys: [
          .isDirectoryKey,
          .fileSizeKey,
          .creationDateKey,
          .contentModificationDateKey,
          .ubiquitousItemDownloadingStatusKey,
          .ubiquitousItemIsDownloadingKey,
          .ubiquitousItemIsUploadedKey,
          .ubiquitousItemIsUploadingKey,
          .ubiquitousItemHasUnresolvedConflictsKey,
        ])
        let containerPath = containerURL.standardizedFileURL.path
        var metadata = mapResourceValues(
          fileURL: fileURL,
          values: values,
          containerPath: containerPath
        )
        metadata["downloadStatus"] = normalizeDownloadStatus(
          values.ubiquitousItemDownloadingStatus
        )
        result(metadata)
      } catch {
        result(nativeCodeError(
          error,
          operation: "getItemMetadata",
          relativePath: relativePath
        ))
      }
    }
  }
  
  /// Lists files in the container using `FileManager.contentsOfDirectory`
  /// with URL resource values for download/upload status.
  ///
  /// Unlike `gather()` (which queries the Spotlight metadata index),
  /// this reads the POSIX filesystem directly and is immediately consistent
  /// after local mutations.
  private func listContents(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String
    else {
      result(argumentError(operation: "listContents"))
      return
    }

    let subdir = args["relativePath"] as? String

    resolveContainerURL(
      containerId: containerId,
      operation: "listContents",
      relativePath: subdir,
      result: result
    ) { [self] containerURL in
      let listURL = subdir != nil
        ? containerURL.appendingPathComponent(subdir!)
        : containerURL

      let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
      ]

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let contents = try FileManager.default.contentsOfDirectory(
            at: listURL,
            includingPropertiesForKeys: keys,
            // Do NOT use .skipsHiddenFiles — iCloud placeholders
            // have a leading dot and would be filtered out.
            options: []
          )

          let containerPath = containerURL.standardizedFileURL.path
          let keysSet = Set(keys)
          let parentRelative = self.relativePath(
            for: listURL, containerPath: containerPath
          )
          var items: [[String: Any?]] = []

          for fileURL in contents {
            let diskName = fileURL.lastPathComponent
            let resolvedName = self.resolveICloudPlaceholderName(diskName)

            // Skip system hidden files (.DS_Store, .Trash, etc.).
            // Placeholder files (.foo.icloud) have already been resolved
            // to their real name, so they pass through this filter.
            if resolvedName.hasPrefix(".") { continue }

            let values = try fileURL.resourceValues(
              forKeys: keysSet
            )

            // Build relative path from the container root so the
            // result is usable with other plugin methods.
            let itemRelativePath = parentRelative.isEmpty
              ? resolvedName
              : parentRelative + "/" + resolvedName

            items.append([
              "relativePath": itemRelativePath,
              "isDirectory": values.isDirectory ?? false,
              "downloadStatus": self.normalizeDownloadStatus(
                values.ubiquitousItemDownloadingStatus
              ),
              "isDownloading":
                values.ubiquitousItemIsDownloading ?? false,
              "isUploaded":
                values.ubiquitousItemIsUploaded ?? false,
              "isUploading":
                values.ubiquitousItemIsUploading ?? false,
              "hasUnresolvedConflicts":
                values.ubiquitousItemHasUnresolvedConflicts ?? false,
            ])
          }

          DispatchQueue.main.async { result(items) }
        } catch {
          DispatchQueue.main.async {
            result(self.nativeCodeError(
              error,
              operation: "listContents",
              relativePath: subdir
            ))
          }
        }
      }
    }
  }

  /// Enumerates unresolved `NSFileVersion` conflict versions for an item
  /// and returns stable descriptors (identifier + modificationDate).
  /// An item with no unresolved versions returns an empty list (not an
  /// error). Conflict policy is app-owned; the plugin only exposes.
  private func enumerateUnresolvedConflictVersions(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "enumerateUnresolvedConflictVersions"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "enumerateUnresolvedConflictVersions",
      relativePath: relativePath,
      result: result
    ) { containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)
      do {
        let descriptors = try VersionExposure.live.enumerate(at: fileURL)
        result(descriptors.map { descriptor -> [String: Any?] in
          [
            "identifier": descriptor.identifier,
            "modificationDate": descriptor.modificationDate?
              .timeIntervalSince1970,
          ]
        })
      } catch {
        result(self.nativeCodeError(
          error,
          operation: "enumerateUnresolvedConflictVersions",
          relativePath: relativePath
        ))
      }
    }
  }

  /// Copies a specific losing version's bytes to a CALLER-PROVIDED
  /// destination URL, leaving the live item untouched. The app owns the
  /// destination path (typically a badged backup under Documents/backups/).
  private func copyConflictVersion(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let versionIdentifier = args["versionIdentifier"] as? String,
          let destinationPath = args["destinationPath"] as? String
    else {
      result(argumentError(operation: "copyConflictVersion"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "copyConflictVersion",
      relativePath: relativePath,
      result: result
    ) { containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)
      let destinationURL = URL(fileURLWithPath: destinationPath)
      do {
        let destinationDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
          try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true,
            attributes: nil
          )
        }
        try VersionExposure.live.copyOut(
          itemURL: fileURL,
          identifier: versionIdentifier,
          to: destinationURL
        )
        result(nil)
      } catch {
        result(self.nativeCodeError(
          error,
          operation: "copyConflictVersion",
          relativePath: relativePath
        ))
      }
    }
  }

  /// Marks unresolved conflict versions resolved (`isResolved = true`)
  /// and, when `removeOtherVersions` is true, removes the other versions.
  /// Invoked ONLY on explicit app request; idempotent and a no-op when
  /// nothing is unresolved. The app must back up losing versions first.
  private func markConflictResolved(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "markConflictResolved"))
      return
    }
    let removeOtherVersions = (args["removeOtherVersions"] as? Bool) ?? false

    resolveContainerURL(
      containerId: containerId,
      operation: "markConflictResolved",
      relativePath: relativePath,
      result: result
    ) { containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)
      do {
        try VersionExposure.live.markResolved(
          at: fileURL,
          removeOthers: removeOtherVersions
        )
        result(nil)
      } catch {
        result(self.nativeCodeError(
          error,
          operation: "markConflictResolved",
          relativePath: relativePath
        ))
      }
    }
  }

  /// Resolves the real filename from an iCloud placeholder name.
  ///
  /// On iOS and pre-Sonoma macOS, non-downloaded files appear as
  /// `.originalName.icloud` (leading dot + `.icloud` suffix). On macOS
  /// Sonoma+ (APFS dataless files), the real name is already used.
  private func resolveICloudPlaceholderName(
    _ diskName: String
  ) -> String {
    guard diskName.hasPrefix("."),
          diskName.hasSuffix(".icloud")
    else {
      return diskName
    }
    let stripped = String(diskName.dropFirst().dropLast(7))
    return stripped.isEmpty ? diskName : stripped
  }

  /// Normalizes metadata-query status strings to clean enum-style values.
  private func normalizeDownloadStatus(_ status: String?) -> String? {
    guard let status else { return nil }
    switch status {
    case NSMetadataUbiquitousItemDownloadingStatusNotDownloaded:
      return "notDownloaded"
    case NSMetadataUbiquitousItemDownloadingStatusDownloaded:
      return "downloaded"
    case NSMetadataUbiquitousItemDownloadingStatusCurrent:
      return "current"
    default:
      return nil
    }
  }

  /// Normalizes `URLUbiquitousItemDownloadingStatus` to clean
  /// enum-style strings for the Dart layer.
  private func normalizeDownloadStatus(
    _ status: URLUbiquitousItemDownloadingStatus?
  ) -> String? {
    guard let status = status else { return nil }
    switch status {
    case .notDownloaded: return "notDownloaded"
    case .downloaded: return "downloaded"
    case .current: return "current"
    default: return nil
    }
  }

  /// Moves a file by copying and removing the original.
  private func moveCloudFile(at: URL, to: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
      }
      try FileManager.default.copyItem(at: at, to: to)
    } catch {
      throw error
    }
  }
  
  /// Deletes an item from the container with coordination, serialized on
  /// the per-path mutation lane (VAL-MUT-002/005/050/051).
  private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError(operation: "delete"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "delete",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      DebugHelper.log("containerURL: \(containerURL.path)")

      let fileURL = containerURL.appendingPathComponent(relativePath)

      Task.detached { [self] in
        do {
          let value: Any? = try await PerPathMutationLane.shared.withLane(
            for: fileURL
          ) {
            try await self.deleteCoordinated(
              fileURL: fileURL,
              relativePath: relativePath
            )
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let mapped = error as? FlutterError ?? self.nativeCodeError(
            error,
            operation: "delete",
            relativePath: relativePath
          )
          DispatchQueue.main.async { result(mapped) }
        }
      }
    }
  }

  /// Coordinated delete honoring the coordinator closure URL. Throws a
  /// typed `FlutterError` on coordination or IO failure (coordErr ??
  /// ioErr — never a silent null/false success). The blocking
  /// `NSFileCoordinator.coordinate(...)` is hopped onto a
  /// `DispatchQueue.global` worker via `CoordinatedIO` so it never
  /// blocks the Swift cooperative pool (same pattern as
  /// `CoordinatedReplaceWriter.liveCoordinateReplace`).
  private func deleteCoordinated(
    fileURL: URL,
    relativePath: String
  ) async throws -> Any? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw itemNotFoundError(operation: "delete", relativePath: relativePath)
    }

    do {
      try await CoordinatedIO.coordinateWriting(
        at: fileURL,
        options: NSFileCoordinator.WritingOptions.forDeleting
      ) { writingURL in
        try FileManager.default.removeItem(at: writingURL)
      }
    } catch let bridgeError as CoordinateBridgeError {
      switch bridgeError {
      case .coordination(let coordinationError):
        throw nativeCodeError(
          coordinationError,
          operation: "delete",
          relativePath: relativePath
        )
      case .accessor(let ioError):
        throw mapFileNotFoundError(
          ioError,
          operation: "delete",
          relativePath: relativePath
        ) ?? nativeCodeError(
          ioError,
          operation: "delete",
          relativePath: relativePath
        )
      }
    }
    return nil
  }
  
  /// Moves an item within the container, serialized against BOTH
  /// endpoint per-path lanes (VAL-MUT-003/041/050/051/054).
  private func move(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let atRelativePath = args["atRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError(operation: "move"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "move",
      relativePath: atRelativePath,
      result: result
    ) { [self] containerURL in
      DebugHelper.log("containerURL: \(containerURL.path)")

      let atURL = containerURL.appendingPathComponent(atRelativePath)
      let toURL = containerURL.appendingPathComponent(toRelativePath)

      Task.detached { [self] in
        do {
          let value: Any? = try await PerPathMutationLane.shared.withLanes(
            for: atURL,
            and: toURL
          ) {
            try await self.moveCoordinated(
              atURL: atURL,
              toURL: toURL,
              atRelativePath: atRelativePath
            )
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let mapped = error as? FlutterError ?? self.nativeCodeError(
            error,
            operation: "move",
            relativePath: atRelativePath
          )
          DispatchQueue.main.async { result(mapped) }
        }
      }
    }
  }

  /// Coordinated move honoring both coordinator closure URLs. Creates
  /// the destination parent directory as needed. Throws a typed
  /// `FlutterError` on coordination or IO failure; preserves the source
  /// on mid-stage failure (VAL-MUT-054). The blocking
  /// `NSFileCoordinator.coordinate(...)` is hopped onto a
  /// `DispatchQueue.global` worker via `CoordinatedIO` so it never
  /// blocks the Swift cooperative pool.
  private func moveCoordinated(
    atURL: URL,
    toURL: URL,
    atRelativePath: String
  ) async throws -> Any? {
    guard FileManager.default.fileExists(atPath: atURL.path) else {
      throw itemNotFoundError(operation: "move", relativePath: atRelativePath)
    }

    do {
      try await CoordinatedIO.coordinateWritingTwo(
        writingAt: atURL,
        options: NSFileCoordinator.WritingOptions.forMoving,
        writingAt: toURL,
        options: NSFileCoordinator.WritingOptions.forReplacing
      ) { atWritingURL, toWritingURL in
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(
            at: toDirURL,
            withIntermediateDirectories: true,
            attributes: nil
          )
        }
        try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
      }
    } catch let bridgeError as CoordinateBridgeError {
      switch bridgeError {
      case .coordination(let coordinationError):
        throw nativeCodeError(
          coordinationError,
          operation: "move",
          relativePath: atRelativePath
        )
      case .accessor(let ioError):
        throw nativeCodeError(
          ioError,
          operation: "move",
          relativePath: atRelativePath
        )
      }
    }
    return nil
  }
  
  /// Copies an item within the container, serialized against BOTH
  /// endpoint per-path lanes (VAL-MUT-004/041/050/051/054).
  private func copy(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let fromRelativePath = args["fromRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError(operation: "copy"))
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "copy",
      relativePath: fromRelativePath,
      result: result
    ) { [self] containerURL in
      DebugHelper.log("containerURL: \(containerURL.path)")

      let fromURL = containerURL.appendingPathComponent(fromRelativePath)
      let toURL = containerURL.appendingPathComponent(toRelativePath)

      Task.detached { [self] in
        do {
          let value: Any? = try await PerPathMutationLane.shared.withLanes(
            for: fromURL,
            and: toURL
          ) {
            try await self.copyCoordinated(
              fromURL: fromURL,
              toURL: toURL,
              fromRelativePath: fromRelativePath,
              toRelativePath: toRelativePath
            )
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let mapped = error as? FlutterError ?? self.nativeCodeError(
            error,
            operation: "copy",
            relativePath: toRelativePath
          )
          DispatchQueue.main.async { result(mapped) }
        }
      }
    }
  }

  /// Coordinated copy honoring the coordinator closure URLs. Surfaces
  /// source-read coordination errors distinctly from destination write
  /// errors (coordErr ?? ioErr). Throws a typed `FlutterError` on
  /// failure; leaves no partial destination on mid-stage failure
  /// (VAL-MUT-054). The blocking `NSFileCoordinator.coordinate(...)`
  /// calls are hopped onto a `DispatchQueue.global` worker via
  /// `CoordinatedIO` so they never block the Swift cooperative pool.
  private func copyCoordinated(
    fromURL: URL,
    toURL: URL,
    fromRelativePath: String,
    toRelativePath: String
  ) async throws -> Any? {
    guard FileManager.default.fileExists(atPath: fromURL.path) else {
      throw itemNotFoundError(operation: "copy", relativePath: fromRelativePath)
    }

    let handledExistingDestination: Bool
    do {
      handledExistingDestination = try await CoordinatedIO.coordinateReadingReturning(
        at: fromURL,
        options: .withoutChanges
      ) { fromReadingURL in
        try self.copyOverwritingExistingItem(
          from: fromReadingURL,
          to: toURL
        )
      }
    } catch let bridgeError as CoordinateBridgeError {
      switch bridgeError {
      case .coordination(let sourceCoordinationError):
        DebugHelper.log("copy source coordination error: \(sourceCoordinationError.localizedDescription)")
        throw nativeCodeError(
          sourceCoordinationError,
          operation: "copy",
          relativePath: fromRelativePath
        )
      case .accessor(let overwriteError):
        DebugHelper.log("copy error: \(overwriteError.localizedDescription)")
        throw nativeCodeError(
          overwriteError,
          operation: "copy",
          relativePath: toRelativePath
        )
      }
    }

    if handledExistingDestination {
      return nil
    }

    // Use reading coordination for source and writing coordination for
    // destination.
    do {
      try await CoordinatedIO.coordinateReadingAndWriting(
        readingAt: fromURL,
        readingOptions: .withoutChanges,
        writingAt: toURL,
        writingOptions: .forReplacing
      ) { fromReadingURL, toWritingURL in
        // Create destination directory if needed.
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(
            at: toDirURL,
            withIntermediateDirectories: true,
            attributes: nil
          )
        }

        // Remove destination file if it exists.
        if FileManager.default.fileExists(atPath: toWritingURL.path) {
          try FileManager.default.removeItem(at: toWritingURL)
        }

        // Copy the file.
        try FileManager.default.copyItem(at: fromReadingURL, to: toWritingURL)
      }
    } catch let bridgeError as CoordinateBridgeError {
      switch bridgeError {
      case .coordination(let copyCoordinationError):
        DebugHelper.log("copy coordination error: \(copyCoordinationError.localizedDescription)")
        throw nativeCodeError(
          copyCoordinationError,
          operation: "copy",
          relativePath: toRelativePath
        )
      case .accessor(let copyIOError):
        DebugHelper.log("copy error: \(copyIOError.localizedDescription)")
        throw nativeCodeError(
          copyIOError,
          operation: "copy",
          relativePath: toRelativePath
        )
      }
    }
    return nil
  }

  private func copyOverwritingExistingItem(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws -> Bool {
    guard FileManager.default.fileExists(atPath: destinationURL.path) else {
      return false
    }

    try CoordinatedReplaceWriter.verifyOverwriteDestinationIsFile(
      at: destinationURL
    )

    let replacementDirectory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: destinationURL,
      create: true
    )
    let replacementURL = replacementDirectory.appendingPathComponent(
      destinationURL.lastPathComponent,
      isDirectory: sourceURL.hasDirectoryPath
    )

    do {
      try FileManager.default.copyItem(at: sourceURL, to: replacementURL)

      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var accessError: Error?

      coordinator.coordinate(
        writingItemAt: destinationURL,
        options: .forReplacing,
        error: &coordinationError
      ) { coordinatedURL in
        do {
          _ = try FileManager.default.replaceItemAt(
            coordinatedURL,
            withItemAt: replacementURL
          )
        } catch {
          accessError = error
        }
      }

      if let coordinationError {
        throw coordinationError
      }

      if let accessError {
        throw accessError
      }
    } catch {
      try? FileManager.default.removeItem(at: replacementDirectory)
      throw error
    }

    try? FileManager.default.removeItem(at: replacementDirectory)
    return true
  }
  
  /// Creates and retains a metadata query session until cleanup completes.
  private func makeMetadataQuerySession(
    query: NSMetadataQuery
  ) -> MetadataQuerySession {
    let session = MetadataQuerySession(query: query) { [weak self] session in
      self?.releaseMetadataQuerySession(session)
    }
    metadataQuerySessionsQueue.sync {
      metadataQuerySessions[session.id] = session
    }
    return session
  }

  /// Releases a metadata query session after observers have been removed and
  /// the query has been stopped.
  private func releaseMetadataQuerySession(
    _ session: MetadataQuerySession
  ) {
    _ = metadataQuerySessionsQueue.sync {
      metadataQuerySessions.removeValue(forKey: session.id)
    }
  }
  
  /// Creates and registers a stream handler for an event channel.
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String,
          !eventChannelName.isEmpty
    else {
      result(argumentError(operation: "createEventChannel"))
      return
    }

    guard let messenger = self.messenger else {
      result(initializationError(operation: "createEventChannel"))
      return
    }

    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    let registration = EventChannelRegistration(
      eventChannel: eventChannel,
      streamHandler: streamHandler
    )
    guard registerEventChannelRegistration(
      registration,
      for: eventChannelName
    ) else {
      result(argumentError(
        operation: "createEventChannel",
        message: "Event channel name is already in use"
      ))
      return
    }
    eventChannel.setStreamHandler(streamHandler)
    result(nil)
  }

  private func failProgressStream(
    eventChannelName: String,
    error: FlutterError
  ) -> Bool {
    guard !eventChannelName.isEmpty,
          let streamHandler = registeredStreamHandler(
            for: eventChannelName
          ) else {
      return false
    }
    let delivered = streamHandler.finish(
      with: [error, FlutterEndOfEventStream]
    )
    removeStreamHandler(eventChannelName)
    return delivered
  }

  /// Removes a stream handler after the Dart cancellation handshake. A
  /// never-listened channel is unregistered immediately because no Dart
  /// subscription exists to cancel it.
  private func removeStreamHandler(_ eventChannelName: String) {
    let registration: EventChannelRegistration? = streamStateQueue.sync {
      () -> EventChannelRegistration? in
      progressByEventChannel.removeValue(forKey: eventChannelName)
      guard let registration = eventChannelRegistrations.removeValue(
        forKey: eventChannelName
      ) else {
        return nil
      }
      retiringEventChannelRegistrations[eventChannelName] = registration
      return registration
    }
    registration?.requestUnregister { [weak self, weak registration] in
      guard let self, let registration else { return }
      self.streamStateQueue.sync {
        if self.retiringEventChannelRegistrations[eventChannelName]
          === registration {
          self.retiringEventChannelRegistrations[eventChannelName] = nil
        }
      }
    }
  }

  /// Emits a monotonic progress update to the Flutter stream.
  private func emitProgress(_ progress: Double, eventChannelName: String) {
    guard let (streamHandler, clamped) = reserveProgressUpdate(
      progress,
      eventChannelName: eventChannelName
    ) else {
      return
    }
    streamHandler.setEvent(clamped)
  }

  private func registeredStreamHandler(
    for eventChannelName: String
  ) -> StreamHandler? {
    streamStateQueue.sync {
      eventChannelRegistrations[eventChannelName]?.streamHandler
    }
  }

  private func hasStreamHandler(named eventChannelName: String) -> Bool {
    streamStateQueue.sync {
      eventChannelRegistrations[eventChannelName]?.streamHandler != nil
    }
  }

  private func registerEventChannelRegistration(
    _ registration: EventChannelRegistration,
    for eventChannelName: String
  ) -> Bool {
    streamStateQueue.sync {
      guard eventChannelRegistrations[eventChannelName] == nil,
            retiringEventChannelRegistrations[eventChannelName] == nil else {
        return false
      }
      eventChannelRegistrations[eventChannelName] = registration
      progressByEventChannel[eventChannelName] = 0
      return true
    }
  }

  private func setDocumentChangeRegistration(
    _ registration: DocumentChangeRegistration,
    for eventChannelName: String
  ) {
    let existingRegistration = documentChangeRegistrationsQueue.sync {
      let existing = documentChangeRegistrations[eventChannelName]
      documentChangeRegistrations[eventChannelName] = registration
      return existing
    }
    existingRegistration?.cancel()
  }

  private func removeDocumentChangeRegistration(
    _ eventChannelName: String,
    matching registration: DocumentChangeRegistration? = nil
  ) -> Bool {
    documentChangeRegistrationsQueue.sync {
      if let registration,
         documentChangeRegistrations[eventChannelName] !== registration {
        return false
      }

      documentChangeRegistrations[eventChannelName] = nil
      return true
    }
  }

  private func reserveProgressUpdate(
    _ progress: Double,
    eventChannelName: String
  ) -> (StreamHandler, Double)? {
    streamStateQueue.sync {
      guard let streamHandler = eventChannelRegistrations[eventChannelName]?.streamHandler else {
        return nil
      }
      let lastProgress = progressByEventChannel[eventChannelName] ?? 0
      let clamped = max(progress, lastProgress)
      progressByEventChannel[eventChannelName] = clamped
      return (streamHandler, clamped)
    }
  }
  
  private func flutterError(
    code: String,
    message: String,
    category: String,
    operation: String,
    retryable: Bool,
    relativePath: String? = nil,
    pathKind: String? = nil,
    nativeError: NSError? = nil,
    underlying: Any? = nil
  ) -> FlutterError {
    var details: [String: Any] = [
      "category": category,
      "operation": operation,
      "retryable": retryable,
    ]
    if let relativePath {
      details["relativePath"] = relativePath
    }
    if let pathKind {
      details["pathKind"] = pathKind
    }
    if let nativeError {
      details["nativeDomain"] = nativeError.domain
      details["nativeCode"] = nativeError.code
      details["nativeDescription"] = nativeError.localizedDescription
      if let nestedError = nativeError.userInfo[NSUnderlyingErrorKey] {
        details["underlying"] = String(describing: nestedError)
      }
    }
    if let underlying {
      details["underlying"] = underlying
    }
    return FlutterError(code: code, message: message, details: details)
  }

  private func argumentError(
    operation: String,
    relativePath: String? = nil,
    pathKind: String? = nil,
    message: String = "Invalid arguments"
  ) -> FlutterError {
    flutterError(
      code: "E_ARG",
      message: message,
      category: "invalidArgument",
      operation: operation,
      retryable: false,
      relativePath: relativePath,
      pathKind: pathKind
    )
  }

  private func initializationError(operation: String) -> FlutterError {
    flutterError(
      code: "E_INIT",
      message: "Plugin not properly initialized",
      category: "initialization",
      operation: operation,
      retryable: false
    )
  }

  private func containerAccessError(
    operation: String,
    relativePath: String? = nil
  ) -> FlutterError {
    flutterError(
      code: "E_CTR",
      message: "Invalid containerId, or user is not signed in, or user disabled iCloud permission",
      category: "containerAccess",
      operation: operation,
      retryable: false,
      relativePath: relativePath
    )
  }

  private func missingEventHandlerError(
    eventChannelName: String,
    operation: String,
    relativePath: String? = nil
  ) -> FlutterError {
    flutterError(
      code: "E_NO_HANDLER",
      message: "Event channel '\(eventChannelName)' not created. Call "
        + "createEventChannel first.",
      category: "invalidArgument",
      operation: operation,
      retryable: false,
      relativePath: relativePath
    )
  }

  private func itemNotFoundError(
    operation: String,
    relativePath: String? = nil,
    code: String = "E_FNF",
    message: String = "The file does not exist",
    nativeError: NSError? = nil,
    pathKind: String? = nil
  ) -> FlutterError {
    flutterError(
      code: code,
      message: message,
      category: "itemNotFound",
      operation: operation,
      retryable: false,
      relativePath: relativePath,
      pathKind: pathKind,
      nativeError: nativeError
    )
  }

  /// Maps file-not-found errors to specific Flutter error codes.
  private func mapFileNotFoundError(
    _ error: Error,
    operation: String = "unknown",
    relativePath: String? = nil,
    pathKind: String? = nil
  ) -> FlutterError? {
    let nsError = error as NSError
    guard nsError.domain == NSCocoaErrorDomain else { return nil }

    switch nsError.code {
    case NSFileNoSuchFileError:
      if operation == "writeInPlace" || operation == "writeInPlaceBytes" {
        return itemNotFoundError(
          operation: operation,
          relativePath: relativePath,
          code: "E_FNF_WRITE",
          message: "The file could not be written because it does not exist",
          nativeError: nsError,
          pathKind: pathKind
        )
      }
      return itemNotFoundError(
        operation: operation,
        relativePath: relativePath,
        nativeError: nsError,
        pathKind: pathKind
      )
    case NSFileReadNoSuchFileError:
      return itemNotFoundError(
        operation: operation,
        relativePath: relativePath,
        code: "E_FNF_READ",
        message: "The file could not be read because it does not exist",
        nativeError: nsError,
        pathKind: pathKind
      )
    default:
      return nil
    }
  }

  /// Wraps a native Error into a FlutterError.
  private func nativeCodeError(
    _ error: Error,
    operation: String = "unknown",
    relativePath: String? = nil,
    pathKind: String? = nil
  ) -> FlutterError {
    let nsError = error as NSError

    if nsError.domain == CoordinatedReplaceWriter.replaceStateErrorDomain {
      switch nsError.code {
      case CoordinatedReplaceWriter.conflictReplaceStateCode:
        return flutterError(
          code: "E_CONFLICT",
          message: nsError.localizedDescription,
          category: "conflict",
          operation: operation,
          retryable: false,
          relativePath: relativePath,
          pathKind: pathKind,
          nativeError: nsError
        )
      case CoordinatedReplaceWriter.directoryReplaceStateCode:
        return flutterError(
          code: "E_ARG",
          message: nsError.localizedDescription,
          category: "invalidArgument",
          operation: operation,
          retryable: false,
          relativePath: relativePath,
          pathKind: pathKind,
          nativeError: nsError
        )
      case CoordinatedReplaceWriter.coordinationReplaceStateCode:
        return flutterError(
          code: "E_COORDINATION",
          message: nsError.localizedDescription,
          category: "coordination",
          operation: operation,
          retryable: false,
          relativePath: relativePath,
          pathKind: pathKind,
          nativeError: nsError
        )
      default:
        break
      }
    }

    if isFileContentWriteOperation(operation)
      && nsError.domain == NSCocoaErrorDomain {
      switch nsError.code {
      case NSFileWriteInvalidFileNameError,
           NSFileWriteUnsupportedSchemeError:
        return flutterError(
          code: "E_ARG",
          message: nsError.localizedDescription,
          category: "invalidArgument",
          operation: operation,
          retryable: false,
          relativePath: relativePath,
          pathKind: pathKind,
          nativeError: nsError
        )
      default:
        break
      }
    }

    return flutterError(
      code: "E_NAT",
      message: "Native Code Error",
      category: "unknownNative",
      operation: operation,
      retryable: false,
      relativePath: relativePath,
      pathKind: pathKind,
      nativeError: nsError,
      underlying: String(describing: error)
    )
  }
}

private final class DocumentChangeRegistration {
  let standardizedPath: String
  let presenter: ICloudDocument
  private let observation: DocumentChangeObservation
  private let cancelLock = NSLock()
  private var didCancel = false

  init(
    documentURL: URL,
    document: ICloudDocument,
    observation: DocumentChangeObservation
  ) {
    standardizedPath = documentURL.standardizedFileURL.path
    presenter = document
    self.observation = observation
  }

  deinit {
    cancel()
  }

  func cancel() {
    let shouldCancel: Bool = {
      cancelLock.lock()
      defer { cancelLock.unlock() }

      guard !didCancel else { return false }
      didCancel = true
      return true
    }()
    guard shouldCancel else { return }

    observation.cancel()
    presenter.changeObservation = nil
  }
}

private final class EventChannelRegistration {
  let streamHandler: StreamHandler
  private let eventChannel: FlutterEventChannel
  private let stateQueue = DispatchQueue(
    label: "icloud_storage_plus.event_channel_registration"
  )
  private enum Lifecycle {
    case neverListened
    case listening
    case cancelled
  }

  private var lifecycle = Lifecycle.neverListened
  private var unregisterRequested = false
  private var unregistered = false
  private var onUnregistered: (() -> Void)?

  init(
    eventChannel: FlutterEventChannel,
    streamHandler: StreamHandler
  ) {
    self.eventChannel = eventChannel
    self.streamHandler = streamHandler
    streamHandler.onListenAcknowledged = { [weak self] in
      self?.listenAcknowledged()
    }
    streamHandler.onCancelAcknowledged = { [weak self] in
      self?.cancelAcknowledged()
    }
  }

  func requestUnregister(onUnregistered: @escaping () -> Void) {
    let lifecycle = stateQueue.sync {
      self.onUnregistered = onUnregistered
      unregisterRequested = true
      return self.lifecycle
    }
    if lifecycle != .listening && !streamHandler.hasPendingEvents {
      unregisterIfNotListening()
    }
  }

  private func unregisterIfNotListening() {
    let claimed = stateQueue.sync { () -> Bool in
      guard lifecycle != .listening && !unregistered else { return false }
      unregistered = true
      return true
    }
    if claimed {
      detachStreamHandler()
    }
  }

  private func listenAcknowledged() {
    stateQueue.sync {
      guard !unregistered else { return }
      lifecycle = .listening
    }
  }

  private func cancelAcknowledged() {
    let claimed = stateQueue.sync { () -> Bool in
      lifecycle = .cancelled
      guard unregisterRequested && !unregistered else { return false }
      unregistered = true
      return true
    }
    if claimed {
      detachStreamHandler()
    }
  }

  private func detachStreamHandler() {
    let detach = { [eventChannel, weak self] in
      eventChannel.setStreamHandler(nil)
      let completion = self?.stateQueue.sync { () -> (() -> Void)? in
        let completion = self?.onUnregistered
        self?.onUnregistered = nil
        return completion
      }
      completion?()
    }
    if Thread.isMainThread {
      detach()
    } else {
      DispatchQueue.main.async(execute: detach)
    }
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private let stateQueue = DispatchQueue(
    label: "icloud_storage_plus.stream_handler"
  )
  private let eventDelivery = StreamEventDelivery<Any>()
  private var listening = false
  private let deferredCancellationHandler = DeferredCancellationHandler()
  var onListenAcknowledged: (() -> Void)?
  var onCancelAcknowledged: (() -> Void)?

  var hasPendingEvents: Bool {
    eventDelivery.hasPendingEvents
  }

  var onCancelHandler: (() -> Void)? {
    get {
      stateQueue.sync {
        deferredCancellationHandler.current
      }
    }
    set {
      let handlerToRun = stateQueue.sync {
        deferredCancellationHandler.install(newValue)
      }
      handlerToRun?()
    }
  }

  /// Starts listening for events from the native side.
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stateQueue.sync {
      deferredCancellationHandler.activate()
      listening = true
    }
    onListenAcknowledged?()
    eventDelivery.listen(events)
    DebugHelper.log("on listen")
    return nil
  }

  /// Stops listening for events from the native side.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let handlerToRun = stateQueue.sync {
      listening = false
      return deferredCancellationHandler.cancel()
    }
    eventDelivery.cancel()
    handlerToRun?()
    onCancelAcknowledged?()
    DebugHelper.log("on cancel")
    return nil
  }

  /// Emits a non-terminal event to the Flutter stream.
  func setEvent(_ data: Any) {
    eventDelivery.emit(data)
  }

  /// Finishes the Flutter stream with a bounded terminal event sequence.
  @discardableResult
  func finish(with terminalEvents: [Any]) -> Bool {
    eventDelivery.finish(terminalEvents)
  }
}

class DebugHelper {
  /// Logs debug output in DEBUG builds.
  public static func log(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}

// FlutterError is an NSObject subclass from the Flutter framework (FlutterMacOS)
// that does not conform to Swift's `Error` protocol. The coordinated
// delete/move/copy mutation helpers throw typed FlutterError instances at the
// channel boundary so the outer catch sites can recover them via
// `error as? FlutterError`. This retroactive conformance bridges the
// Objective-C type into Swift's error machinery so `throw FlutterError`
// compiles. If Swift 6 language mode is ever enabled, this must become
// `extension FlutterError: @retroactive Error {}`.
extension FlutterError: Error {}
