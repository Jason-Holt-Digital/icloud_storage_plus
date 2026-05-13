import Cocoa
import FlutterMacOS

public class ICloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  private var streamHandlers: [String: StreamHandler] = [:]
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
  private let fileCoordinatorQueue = DispatchQueue(
    label: "icloud_storage_plus.file_coordinator",
    qos: .userInitiated
  )
  private let ubiquityContainerResolver: UbiquityContainerResolver

  init(
    ubiquityContainerResolver: UbiquityContainerResolver = .live
  ) {
    self.ubiquityContainerResolver = ubiquityContainerResolver
    super.init()
  }

  deinit {
    let sessions = metadataQuerySessionsQueue.sync {
      Array(metadataQuerySessions.values)
    }
    for session in sessions {
      session.cancel()
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
    case "getDocumentMetadata":
      getDocumentMetadata(call, result)
    case "getItemMetadata":
      getItemMetadata(call, result)
    case "listContents":
      listContents(call, result)
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
    onResolved: @escaping (URL) -> Void
  ) {
    Task { @MainActor [self] in
      guard let containerURL = await ubiquityContainerResolver.resolve(
        containerId: containerId
      ) else {
        result(containerAccessError(
          operation: operation,
          relativePath: relativePath
        ))
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
      result(argumentError)
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
      result(argumentError)
      return
    }

    resolveContainerURL(
      containerId: containerId,
      operation: "gather",
      result: result
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

    // Verify event channel handler exists before registering observers
    var streamHandler: StreamHandler?
    if !eventChannelName.isEmpty {
      guard let handler = registeredStreamHandler(for: eventChannelName) else {
        result(FlutterError(code: "E_NO_HANDLER", message: "Event channel '\(eventChannelName)' not created. Call createEventChannel first.", details: nil))
        return
      }
      streamHandler = handler
    }

    let query = NSMetadataQuery.init()
    query.operationQueue = metadataQueryOperationQueue
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    let session = makeMetadataQuerySession(query: query)
    addGatherFilesObservers(
      session: session,
      containerURL: containerURL,
      eventChannelName: eventChannelName,
      result: result
    )

    if let streamHandler {
      streamHandler.onCancelHandler = { [weak self, weak session] in
        session?.cancel()
        self?.removeStreamHandler(eventChannelName)
      }
    }
    session.start()
  }
  
  /// Adds observers for metadata gather and update notifications.
  private func addGatherFilesObservers(session: MetadataQuerySession, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
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
      if eventChannelName.isEmpty {
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
      "downloadStatus": item.value(
        forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
      ) as? String,
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
      "downloadStatus": values.ubiquitousItemDownloadingStatus?.rawValue,
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
    ) ?? mapTimeoutError(
      error,
      operation: operation,
      relativePath: relativePath,
      pathKind: "containerRelative"
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
          let cloudRelativePath = args["cloudRelativePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    let localFileURL = URL(fileURLWithPath: localFilePath)

    Task { @MainActor [self] in
      let cloudFileURL: URL
      do {
        cloudFileURL = try await prepareWriteEntrypointURL(
          containerId: containerId,
          relativePath: cloudRelativePath
        )
      } catch {
        result(mapWriteEntrypointPreflightError(
          error,
          operation: "uploadFile",
          relativePath: cloudRelativePath
        ))
        return
      }

      DebugHelper.log("containerURL: \(cloudFileURL.deletingLastPathComponent().path)")
      writeDocument(at: cloudFileURL, sourceURL: localFileURL) { error in
        if let error = error {
          let mapped = self.mapTimeoutError(
            error,
            operation: "uploadFile",
            relativePath: cloudRelativePath
          ) ?? self.nativeCodeError(
            error,
            operation: "uploadFile",
            relativePath: cloudRelativePath
          )
          result(mapped)
        } else {
          // Set up progress monitoring if needed
          if !eventChannelName.isEmpty {
            self.setupUploadProgressMonitoring(
              cloudFileURL: cloudFileURL,
              cloudRelativePath: cloudRelativePath,
              eventChannelName: eventChannelName
            )
          }
          result(nil)
        }
      }
    }
  }
  
  /// Starts a metadata query to report upload progress.
  private func setupUploadProgressMonitoring(
    cloudFileURL: URL,
    cloudRelativePath: String,
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
      cloudRelativePath: cloudRelativePath,
      eventChannelName: eventChannelName
    )

    session.start()
  }
  
  /// Adds observers for upload progress updates.
  private func addUploadObservers(
    session: MetadataQuerySession,
    cloudRelativePath: String,
    eventChannelName: String
  ) {
    session.addObserver(
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [weak self] session, query, _ in
      guard let self else { return }
      onUploadQueryNotification(
        session: session,
        query: query,
        cloudRelativePath: cloudRelativePath,
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
        cloudRelativePath: cloudRelativePath,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits upload progress updates to the event channel.
  private func onUploadQueryNotification(
    session: MetadataQuerySession,
    query: NSMetadataQuery,
    cloudRelativePath: String,
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
      streamHandler.setEvent(nativeCodeError(
        error,
        operation: "uploadFile",
        relativePath: cloudRelativePath
      ))
      streamHandler.setEvent(FlutterEndOfEventStream)
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
        streamHandler.setEvent(FlutterEndOfEventStream)
        session.cancel()
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  /// Downloads an iCloud item if needed, then copies it out to a local path.
  private func downloadFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudRelativePath = args["cloudRelativePath"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    resolveContainerURL(
      containerId: containerId,
      operation: "downloadFile",
      relativePath: cloudRelativePath,
      result: result
    ) { [self] containerURL in
      DebugHelper.log("containerURL: \(containerURL.path)")

      let cloudFileURL = containerURL.appendingPathComponent(cloudRelativePath)
      let localFileURL = URL(fileURLWithPath: localFilePath)
      do {
        try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
      } catch {
        let mapped = mapFileNotFoundError(
          error,
          operation: "downloadFile",
          relativePath: cloudRelativePath
        ) ?? nativeCodeError(
          error,
          operation: "downloadFile",
          relativePath: cloudRelativePath
        )
        result(mapped)
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
          downloadSession?.cancel()
          self?.removeStreamHandler(eventChannelName)
          completeOnce(
            FlutterError(
              code: "E_CANCEL",
              message: "Download canceled",
              details: nil
            )
          )
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
            relativePath: cloudRelativePath
          ) ?? nativeCodeError(
            error,
            operation: "downloadFile",
            relativePath: cloudRelativePath
          )
          downloadStreamHandler?.setEvent(mapped)
          downloadStreamHandler?.setEvent(FlutterEndOfEventStream)
          downloadSession?.cancel()
          removeStreamHandler(eventChannelName)
          completeOnce(mapped)
          return
        }

        emitProgress(100.0, eventChannelName: eventChannelName)
        downloadStreamHandler?.setEvent(FlutterEndOfEventStream)
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
      result(argumentError)
      return
    }

    let idleTimeouts = (args["idleTimeoutSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []
    let retryBackoff = (args["retryBackoffSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []

    resolveContainerURL(
      containerId: containerId,
      operation: "readInPlace",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)

      do {
        try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
      } catch {
        let mapped = mapFileNotFoundError(
          error,
          operation: "readInPlace",
          relativePath: relativePath
        ) ?? nativeCodeError(
          error,
          operation: "readInPlace",
          relativePath: relativePath
        )
        result(mapped)
        return
      }

      Task { @MainActor [self] in
        do {
          try await waitForDownloadCompletion(
            at: fileURL,
            idleTimeouts: idleTimeouts,
            retryBackoff: retryBackoff
          )
        } catch {
          if let timeoutError = mapTimeoutError(
            error,
            operation: "readInPlace",
            relativePath: relativePath
          ) {
            result(timeoutError)
            return
          }
          result(nativeCodeError(
            error,
            operation: "readInPlace",
            relativePath: relativePath
          ))
          return
        }

        readInPlaceDocument(at: fileURL) { [self] contents, error in
          if let error = error {
            let mapped = mapFileNotFoundError(
              error,
              operation: "readInPlace",
              relativePath: relativePath
            ) ?? nativeCodeError(
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
      result(argumentError)
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

      writeInPlaceDocument(at: fileURL, contents: contents) { [self] error in
        if let error = error {
          let mapped = mapNativeWriteError(
            error,
            operation: "writeInPlace",
            relativePath: relativePath,
            destinationURL: fileURL
          )
          result(mapped)
          return
        }
        result(nil)
      }
    }
  }

  /// Read a file in place as bytes from the iCloud container using coordinated access.
  private func readInPlaceBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }

    let idleTimeouts = (args["idleTimeoutSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []
    let retryBackoff = (args["retryBackoffSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []

    resolveContainerURL(
      containerId: containerId,
      operation: "readInPlaceBytes",
      relativePath: relativePath,
      result: result
    ) { [self] containerURL in
      let fileURL = containerURL.appendingPathComponent(relativePath)

      do {
        try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
      } catch {
        let mapped = mapFileNotFoundError(
          error,
          operation: "readInPlaceBytes",
          relativePath: relativePath
        ) ?? nativeCodeError(
          error,
          operation: "readInPlaceBytes",
          relativePath: relativePath
        )
        result(mapped)
        return
      }

      Task { @MainActor [self] in
        do {
          try await waitForDownloadCompletion(
            at: fileURL,
            idleTimeouts: idleTimeouts,
            retryBackoff: retryBackoff
          )
        } catch {
          if let timeoutError = mapTimeoutError(
            error,
            operation: "readInPlaceBytes",
            relativePath: relativePath
          ) {
            result(timeoutError)
            return
          }
          result(nativeCodeError(
            error,
            operation: "readInPlaceBytes",
            relativePath: relativePath
          ))
          return
        }

        readInPlaceBinaryDocument(at: fileURL) { [self] contents, error in
          if let error = error {
            let mapped = mapFileNotFoundError(
              error,
              operation: "readInPlaceBytes",
              relativePath: relativePath
            ) ?? nativeCodeError(
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
      result(argumentError)
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

      writeInPlaceBinaryDocument(at: fileURL, contents: contents.data) {
        [self] error in
        if let error = error {
          let mapped = mapNativeWriteError(
            error,
            operation: "writeInPlaceBytes",
            relativePath: relativePath,
            destinationURL: fileURL
          )
          result(mapped)
          return
        }
        result(nil)
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
      result(argumentError)
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

  /// Get file or directory metadata without downloading content.
  /// Returns a map that includes `isDirectory` when the item exists.
  private func getDocumentMetadata(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    resolveContainerURL(
      containerId: containerId,
      operation: "getDocumentMetadata",
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
        result(mapResourceValues(
          fileURL: fileURL,
          values: values,
          containerPath: containerURL.standardizedFileURL.path
        ))
      } catch {
        result(nativeCodeError(
          error,
          operation: "getDocumentMetadata",
          relativePath: relativePath
        ))
      }
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
      result(argumentError)
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
        ) ?? values.ubiquitousItemDownloadingStatus?.rawValue
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
      result(argumentError)
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
  
  /// Deletes an item from the container with coordination.
  private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
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
      let completionGate = CompletionGate()
      let completeOnce: (Any?) -> Void = { value in
        guard completionGate.tryComplete() else { return }
        DispatchQueue.main.async { result(value) }
      }

      fileCoordinatorQueue.async { [self] in
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          completeOnce(itemNotFoundError(
            operation: "delete",
            relativePath: relativePath
          ))
          return
        }

        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        fileCoordinator.coordinate(
          writingItemAt: fileURL,
          options: NSFileCoordinator.WritingOptions.forDeleting,
          error: &coordinationError
        ) { writingURL in
          do {
            try FileManager.default.removeItem(at: writingURL)
            completeOnce(nil)
          } catch {
            DebugHelper.log("error: \(error.localizedDescription)")
            let mapped = mapFileNotFoundError(
              error,
              operation: "delete",
              relativePath: relativePath
            ) ?? nativeCodeError(
              error,
              operation: "delete",
              relativePath: relativePath
            )
            completeOnce(mapped)
          }
        }

        if let coordinationError {
          completeOnce(nativeCodeError(
            coordinationError,
            operation: "delete",
            relativePath: relativePath
          ))
        }
      }
    }
  }
  
  /// Moves an item within the container.
  private func move(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let atRelativePath = args["atRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
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
      let completionGate = CompletionGate()
      let completeOnce: (Any?) -> Void = { value in
        guard completionGate.tryComplete() else { return }
        DispatchQueue.main.async { result(value) }
      }

      fileCoordinatorQueue.async { [self] in
        guard FileManager.default.fileExists(atPath: atURL.path) else {
          completeOnce(itemNotFoundError(
            operation: "move",
            relativePath: atRelativePath
          ))
          return
        }

        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        fileCoordinator.coordinate(
          writingItemAt: atURL,
          options: NSFileCoordinator.WritingOptions.forMoving,
          writingItemAt: toURL,
          options: NSFileCoordinator.WritingOptions.forReplacing,
          error: &coordinationError
        ) { atWritingURL, toWritingURL in
          do {
            let toDirURL = toWritingURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: toDirURL.path) {
              try FileManager.default.createDirectory(
                at: toDirURL,
                withIntermediateDirectories: true,
                attributes: nil
              )
            }
            try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
            completeOnce(nil)
          } catch {
            DebugHelper.log("error: \(error.localizedDescription)")
            completeOnce(nativeCodeError(
              error,
              operation: "move",
              relativePath: atRelativePath
            ))
          }
        }

        if let coordinationError {
          completeOnce(nativeCodeError(
            coordinationError,
            operation: "move",
            relativePath: atRelativePath
          ))
        }
      }
    }
  }
  
  /// Copies an item within the container.
  private func copy(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let fromRelativePath = args["fromRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
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
      guard FileManager.default.fileExists(atPath: fromURL.path) else {
        result(itemNotFoundError(operation: "copy", relativePath: fromRelativePath))
        return
      }

      let toURL = containerURL.appendingPathComponent(toRelativePath)
      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      var handledExistingDestination = false
      var overwriteError: Error?
      var sourceCoordinationError: NSError?

      fileCoordinator.coordinate(
        readingItemAt: fromURL,
        options: .withoutChanges,
        error: &sourceCoordinationError
      ) { fromReadingURL in
        do {
          handledExistingDestination = try copyOverwritingExistingItem(
            from: fromReadingURL,
            to: toURL
          )
        } catch {
          overwriteError = error
        }
      }

      if let sourceCoordinationError {
        DebugHelper.log("copy source coordination error: \(sourceCoordinationError.localizedDescription)")
        result(nativeCodeError(
          sourceCoordinationError,
          operation: "copy",
          relativePath: fromRelativePath
        ))
        return
      }

      if let overwriteError {
        DebugHelper.log("copy error: \(overwriteError.localizedDescription)")
        result(nativeCodeError(
          overwriteError,
          operation: "copy",
          relativePath: toRelativePath
        ))
        return
      }

      if handledExistingDestination {
        result(nil)
        return
      }

      // Use reading coordination for source and writing coordination for destination
      var copyCoordinationError: NSError?
      fileCoordinator.coordinate(
        readingItemAt: fromURL,
        options: .withoutChanges,
        writingItemAt: toURL,
        options: .forReplacing,
        error: &copyCoordinationError
      ) { fromReadingURL, toWritingURL in
        do {
          // Create destination directory if needed
          let toDirURL = toWritingURL.deletingLastPathComponent()
          if !FileManager.default.fileExists(atPath: toDirURL.path) {
            try FileManager.default.createDirectory(
              at: toDirURL,
              withIntermediateDirectories: true,
              attributes: nil
            )
          }

          // Remove destination file if it exists
          if FileManager.default.fileExists(atPath: toWritingURL.path) {
            try FileManager.default.removeItem(at: toWritingURL)
          }

          // Copy the file
          try FileManager.default.copyItem(at: fromReadingURL, to: toWritingURL)
          result(nil)
        } catch {
          DebugHelper.log("copy error: \(error.localizedDescription)")
          result(nativeCodeError(
            error,
            operation: "copy",
            relativePath: toRelativePath
          ))
        }
      }

      if let copyCoordinationError {
        DebugHelper.log("copy coordination error: \(copyCoordinationError.localizedDescription)")
        result(nativeCodeError(
          copyCoordinationError,
          operation: "copy",
          relativePath: toRelativePath
        ))
      }
    }
  }

  private func copyOverwritingExistingItem(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws -> Bool {
    guard FileManager.default.fileExists(atPath: destinationURL.path) else {
      return false
    }

    try CoordinatedReplaceWriter.verifyExistingDestinationCanBeReplaced(
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
    metadataQuerySessionsQueue.sync {
      metadataQuerySessions.removeValue(forKey: session.id)
    }
  }
  
  /// Creates and registers a stream handler for an event channel.
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }

    guard let messenger = self.messenger else {
      result(initializationError)
      return
    }

    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(streamHandler)
    setStreamHandler(streamHandler, for: eventChannelName)

    result(nil)
  }
  
  /// Removes a stream handler for the given event channel.
  private func removeStreamHandler(_ eventChannelName: String) {
    streamStateQueue.sync {
      streamHandlers[eventChannelName] = nil
      progressByEventChannel.removeValue(forKey: eventChannelName)
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
      streamHandlers[eventChannelName]
    }
  }

  private func hasStreamHandler(named eventChannelName: String) -> Bool {
    streamStateQueue.sync {
      streamHandlers[eventChannelName] != nil
    }
  }

  private func setStreamHandler(
    _ streamHandler: StreamHandler,
    for eventChannelName: String
  ) {
    streamStateQueue.sync {
      streamHandlers[eventChannelName] = streamHandler
      progressByEventChannel[eventChannelName] = 0
    }
  }

  private func reserveProgressUpdate(
    _ progress: Double,
    eventChannelName: String
  ) -> (StreamHandler, Double)? {
    streamStateQueue.sync {
      guard let streamHandler = streamHandlers[eventChannelName] else {
        return nil
      }
      let lastProgress = progressByEventChannel[eventChannelName] ?? 0
      let clamped = max(progress, lastProgress)
      progressByEventChannel[eventChannelName] = clamped
      return (streamHandler, clamped)
    }
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let initializationError = FlutterError(code: "E_INIT", message: "Plugin not properly initialized", details: nil)

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

  private func timeoutError(
    operation: String,
    relativePath: String? = nil,
    nativeError: NSError? = nil,
    pathKind: String? = nil
  ) -> FlutterError {
    flutterError(
      code: "E_TIMEOUT",
      message: "The download did not make progress before timing out",
      category: "timeout",
      operation: operation,
      retryable: true,
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
      case CoordinatedReplaceWriter.itemNotDownloadedReplaceStateCode:
        return flutterError(
          code: "E_NOT_DOWNLOADED",
          message: nsError.localizedDescription,
          category: "itemNotDownloaded",
          operation: operation,
          retryable: true,
          relativePath: relativePath,
          pathKind: pathKind,
          nativeError: nsError
        )
      case CoordinatedReplaceWriter.downloadInProgressReplaceStateCode:
        return flutterError(
          code: "E_DOWNLOAD_IN_PROGRESS",
          message: nsError.localizedDescription,
          category: "downloadInProgress",
          operation: operation,
          retryable: true,
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

  private func mapTimeoutError(
    _ error: Error,
    operation: String = "unknown",
    relativePath: String? = nil,
    pathKind: String? = nil
  ) -> FlutterError? {
    let nsError = error as NSError
    guard nsError.domain == "ICloudStorageTimeout" else { return nil }
    return timeoutError(
      operation: operation,
      relativePath: relativePath,
      nativeError: nsError,
      pathKind: pathKind
    )
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private let stateQueue = DispatchQueue(
    label: "icloud_storage_plus.stream_handler"
  )
  private var eventSink: FlutterEventSink?
  private var cancelHandler: (() -> Void)?
  private var isCancelled = false

  var onCancelHandler: (() -> Void)? {
    get {
      stateQueue.sync {
        cancelHandler
      }
    }
    set {
      stateQueue.sync {
        cancelHandler = newValue
      }
    }
  }

  /// Starts listening for events from the native side.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stateQueue.sync {
      isCancelled = false
      eventSink = events
    }
    DebugHelper.log("on listen")
    return nil
  }

  /// Stops listening for events from the native side.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let onCancelHandler = stateQueue.sync { () -> (() -> Void)? in
      isCancelled = true
      eventSink = nil
      return cancelHandler
    }
    onCancelHandler?()
    DebugHelper.log("on cancel")
    return nil
  }

  /// Emits an event to the Flutter stream.
  func setEvent(_ data: Any) {
    stateQueue.sync {
      if isCancelled {
        return
      }
      eventSink?(data)
    }
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
