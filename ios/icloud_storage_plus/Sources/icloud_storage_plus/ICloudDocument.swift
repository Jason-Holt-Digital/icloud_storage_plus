import UIKit

/// UIDocument subclass for handling iCloud documents with streaming IO.
/// Provides conflict resolution and safe, coordinated file access.
class ICloudDocument: UIDocument {
    struct StreamPayload {
        let sourceURL: URL
    }

    /// Source file for streaming writes.
    var sourceURL: URL?

    /// Destination file for streaming reads.
    var destinationURL: URL?

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    // MARK: - UIDocument Override Methods

    override func contents(forType typeName: String) throws -> Any {
        guard let sourceURL = sourceURL else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Missing source URL"]
            )
        }
        return StreamPayload(sourceURL: sourceURL)
    }

    override func writeContents(
        _ contents: Any,
        andAttributes attributes: [AnyHashable : Any]?,
        safelyTo url: URL,
        for saveOperation: UIDocument.SaveOperation
    ) throws {
        guard let payload = contents as? StreamPayload else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Invalid write payload"]
            )
        }

        do {
            try streamCopy(from: payload.sourceURL, to: url)
        } catch {
            lastError = error
            throw error
        }
    }

    override func read(from url: URL) throws {
        guard let destinationURL = destinationURL else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Missing destination URL"]
            )
        }

        do {
            try streamCopy(from: url, to: destinationURL)
        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - Initialization and Deinitialization

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        setupStateChangeObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Conflict Resolution

    private func setupStateChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentStateChanged),
            name: UIDocument.stateChangedNotification,
            object: self
        )
    }

    @objc private func documentStateChanged() {
        if documentState.contains(.inConflict) {
            // Conflict policy is app-owned. The plugin only surfaces the
            // conflict; it never auto-resolves-and-deletes losing
            // `NSFileVersion`s. The app enumerates, copies out, and marks
            // resolved via the dedicated version-exposure primitives.
            DebugHelper.log(
                "Document in conflict: \(fileURL.lastPathComponent)"
            )
        }

        if documentState.contains(.savingError) {
            DebugHelper.log("Document saving error: \(fileURL.lastPathComponent)")
        }

        if documentState.contains(.editingDisabled) {
            DebugHelper.log("Document editing disabled: \(fileURL.lastPathComponent)")
        }
    }

    private func streamCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let destinationDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.createDirectory(
                at: destinationDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        guard let input = InputStream(url: sourceURL) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open input stream"]
            )
        }

        guard let output = OutputStream(url: destinationURL, append: false) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open output stream"]
            )
        }

        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while input.hasBytesAvailable {
            let read = input.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw input.streamError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Stream read error"]
                )
            }
            if read == 0 {
                break
            }

            var totalWritten = 0
            while totalWritten < read {
                let written = buffer.withUnsafeBytes { rawBuffer -> Int in
                    let base = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    return output.write(base.advanced(by: totalWritten), maxLength: read - totalWritten)
                }
                // `OutputStream.write` returns the number of bytes written or -1 on error.
                // While rare for file-backed streams, it can also return 0. In a tight loop,
                // a 0-byte write would spin forever; fail fast rather than hang the app.
                if written <= 0 {
                    let message = written == 0
                        ? "Stream write returned 0 bytes (stalled); treating as failure"
                        : "Stream write error"
                    throw output.streamError ?? NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileWriteUnknownError,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                }
                totalWritten += written
            }
        }
    }
}

/// UIDocument subclass for coordinated in-place text access.
final class ICloudInPlaceDocument: UIDocument {
    /// Text contents for in-place reads/writes.
    var textContents: String = ""

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    override func contents(forType typeName: String) throws -> Any {
        return textContents.data(using: .utf8) ?? Data()
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        if let data = contents as? Data {
            if data.isEmpty {
                textContents = ""
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported text encoding"]
                )
            }
            textContents = text
            return
        }

        if let fileWrapper = contents as? FileWrapper,
           let data = fileWrapper.regularFileContents {
            if data.isEmpty {
                textContents = ""
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported text encoding"]
                )
            }
            textContents = text
            return
        }

        if let text = contents as? String {
            textContents = text
            return
        }

        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported document contents"]
        )
    }

    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        lastError = error
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}

/// UIDocument subclass for coordinated in-place binary access.
final class ICloudInPlaceBinaryDocument: UIDocument {
    /// Binary contents for in-place reads/writes.
    var dataContents: Data = Data()

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    override func contents(forType typeName: String) throws -> Any {
        return dataContents
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        if let data = contents as? Data {
            dataContents = data
            return
        }

        if let fileWrapper = contents as? FileWrapper,
           let data = fileWrapper.regularFileContents {
            dataContents = data
            return
        }

        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported document contents"]
        )
    }

    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        lastError = error
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}

// MARK: - Extension for Document Operations

extension ICloudStoragePlugin {
    /// Read a document from iCloud using UIDocument streaming.
    /// - Parameters:
    ///   - url: The URL of the document to read
    ///   - destinationURL: The local URL to write to
    ///   - completion: Completion handler with optional error
    func readDocumentAt(
        url: URL,
        destinationURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        let document = ICloudDocument(fileURL: url)
        document.destinationURL = destinationURL

        document.open { success in
            if success {
                completion(nil)
                document.close { _ in
                    DebugHelper.log("Document closed: \(url.lastPathComponent)")
                }
            } else {
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open document"]
                )
                completion(error)
            }
        }
    }

    /// Write a document to iCloud using UIDocument streaming.
    /// - Parameters:
    ///   - url: The URL where the document should be saved
    ///   - sourceURL: The local file URL to read from
    ///   - completion: Completion handler with optional error
    func writeDocument(
        at url: URL,
        sourceURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        performBackgroundOverwriteIfNeeded(
            at: url,
            prepareReplacementFile: { replacementURL in
                try streamCopyToURL(from: sourceURL, to: replacementURL)
            },
            completion: completion
        ) {
            let document = ICloudDocument(fileURL: url)
            document.sourceURL = sourceURL

            document.save(to: url, for: .forCreating) { success in
                if success {
                    document.close { _ in
                        completion(nil)
                    }
                } else {
                    let error = document.lastError ?? NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileWriteUnknownError,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to save document"]
                    )
                    completion(error)
                }
            }
        }
    }

    /// Check document state and conflicts.
    func checkDocumentState(
        at url: URL,
        completion: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let document = ICloudDocument(fileURL: url)

        document.open { success in
            if success {
                var stateInfo: [String: Any] = [:]

                stateInfo["hasConflicts"] = document.documentState.contains(.inConflict)
                stateInfo["hasUnsavedChanges"] = document.hasUnsavedChanges
                stateInfo["isEditingDisabled"] = document.documentState.contains(.editingDisabled)
                stateInfo["isClosed"] = document.documentState.contains(.closed)
                stateInfo["isNormal"] = document.documentState.contains(.normal)
                stateInfo["isSavingError"] = document.documentState.contains(.savingError)

                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    stateInfo["modificationDate"] = modificationDate.timeIntervalSince1970
                }

                if let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
                    stateInfo["conflictCount"] = conflictVersions.count
                }

                document.close { _ in
                    completion(stateInfo, nil)
                }
            } else {
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open document"]
                )
                completion(nil, error)
            }
        }
    }

    /// Read a document in place using UIDocument coordination.
    func readInPlaceDocument(
        at url: URL,
        completion: @escaping (String?, Error?) -> Void
    ) {
        let document = ICloudInPlaceDocument(fileURL: url)

        document.open { success in
            if success {
                let contents = document.textContents
                document.close { _ in
                    completion(contents, nil)
                }
            } else {
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open document"]
                )
                completion(nil, error)
            }
        }
    }

    /// Read a binary document in place using UIDocument coordination.
    func readInPlaceBinaryDocument(
        at url: URL,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        let document = ICloudInPlaceBinaryDocument(fileURL: url)

        document.open { success in
            if success {
                let contents = document.dataContents
                document.close { _ in
                    completion(contents, nil)
                }
            } else {
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open document"]
                )
                completion(nil, error)
            }
        }
    }

    /// Write a document in place using UIDocument coordination.
    func writeInPlaceDocument(
        at url: URL,
        contents: String,
        completion: @escaping (Error?) -> Void
    ) {
        performBackgroundOverwriteIfNeeded(
            at: url,
            prepareReplacementFile: { replacementURL in
                try writeTextToURL(contents, to: replacementURL)
            },
            completion: completion
        ) {
            let document = ICloudInPlaceDocument(fileURL: url)
            document.textContents = contents

            document.save(to: url, for: .forCreating) { success in
                if success {
                    document.close { _ in
                        completion(nil)
                    }
                } else {
                    let error = document.lastError ?? NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileWriteUnknownError,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to save document"]
                    )
                    completion(error)
                }
            }
        }
    }

    /// Write a binary document in place using UIDocument coordination.
    func writeInPlaceBinaryDocument(
        at url: URL,
        contents: Data,
        completion: @escaping (Error?) -> Void
    ) {
        performBackgroundOverwriteIfNeeded(
            at: url,
            prepareReplacementFile: { replacementURL in
                try writeDataToURL(contents, to: replacementURL)
            },
            completion: completion
        ) {
            let document = ICloudInPlaceBinaryDocument(fileURL: url)
            document.dataContents = contents

            document.save(to: url, for: .forCreating) { success in
                if success {
                    document.close { _ in
                        completion(nil)
                    }
                } else {
                    let error = document.lastError ?? NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileWriteUnknownError,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to save document"]
                    )
                    completion(error)
                }
            }
        }
    }
}

private func performBackgroundOverwriteIfNeeded(
    at url: URL,
    prepareReplacementFile: @escaping (URL) throws -> Void,
    completion: @escaping (Error?) -> Void,
    fallbackCreate: @escaping () -> Void
) {
    Task.detached(priority: .userInitiated) {
        do {
            let handled = try await CoordinatedReplaceWriter.live
                .overwriteExistingItem(
                    at: url,
                    prepareReplacementFile: prepareReplacementFile
                )

            if handled {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
            return
        }

        DispatchQueue.main.async(execute: fallbackCreate)
    }
}
