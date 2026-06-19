import Cocoa

/// NSDocument subclass for handling iCloud documents with streaming IO.
class ICloudDocument: NSDocument {
    /// Source file for streaming writes.
    var sourceURL: URL?

    /// Destination file for streaming reads.
    var destinationURL: URL?

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    // MARK: - NSDocument Override Methods

    override func read(from url: URL, ofType typeName: String) throws {
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

    override func write(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        originalContentsURL: URL?
    ) throws {
        guard let sourceURL = sourceURL else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Missing source URL"]
            )
        }
        do {
            try streamCopy(from: sourceURL, to: url)
        } catch {
            lastError = error
            throw error
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Data tier is unsupported"]
        )
    }

    override func read(from data: Data, ofType typeName: String) throws {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Data tier is unsupported"]
        )
    }

    // MARK: - Conflict Resolution

    override class var autosavesInPlace: Bool {
        return true
    }

    override func presentedItemDidChange() {
        super.presentedItemDidChange()

        guard let fileURL = fileURL else { return }
        guard let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL),
              !conflictVersions.isEmpty else {
            return
        }

        // Conflict policy is app-owned. The plugin only surfaces the
        // conflict; it never auto-resolves-and-deletes losing
        // `NSFileVersion`s. The app enumerates, copies out, and marks
        // resolved via the dedicated version-exposure primitives.
        DebugHelper.log(
            "Document in conflict: \(fileURL.lastPathComponent)"
        )
    }

    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        DebugHelper.log("Document moved to: \(newURL.lastPathComponent)")
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

/// NSDocument subclass for coordinated in-place text access.
final class ICloudInPlaceDocument: NSDocument {
    /// Text contents for in-place reads/writes.
    var textContents: String = ""

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    override class var autosavesInPlace: Bool {
        return true
    }

    override func data(ofType typeName: String) throws -> Data {
        return textContents.data(using: .utf8) ?? Data()
    }

    override func read(from data: Data, ofType typeName: String) throws {
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
    }
}

/// NSDocument subclass for coordinated in-place binary access.
final class ICloudInPlaceBinaryDocument: NSDocument {
    /// Binary contents for in-place reads/writes.
    var dataContents: Data = Data()

    /// Error occurred during the last operation (if any).
    var lastError: Error?

    override class var autosavesInPlace: Bool {
        return true
    }

    override func data(ofType typeName: String) throws -> Data {
        return dataContents
    }

    override func read(from data: Data, ofType typeName: String) throws {
        dataContents = data
    }
}

// MARK: - Extension for Document Operations

extension ICloudStoragePlugin {
    /// Read a document from iCloud using NSDocument streaming.
    func readDocumentAt(
        url: URL,
        destinationURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        let document = ICloudDocument()
        document.destinationURL = destinationURL

        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { document.close() } }
            do {
                try document.read(from: url, ofType: "public.data")
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    /// Write a document to iCloud using NSDocument streaming.
    func writeDocument(
        at url: URL,
        sourceURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                let handled = try await CoordinatedReplaceWriter.live
                    .overwriteExistingItem(at: url) { replacementURL in
                        try streamCopyToURL(from: sourceURL, to: replacementURL)
                    }

                if handled {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let document = ICloudDocument()
                document.sourceURL = sourceURL
                defer { DispatchQueue.main.async { document.close() } }

                try document.write(
                    to: url,
                    ofType: "public.data",
                    for: .saveAsOperation,
                    originalContentsURL: nil
                )
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
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
        DispatchQueue.global(qos: .userInitiated).async {
            var stateInfo: [String: Any] = [:]

            let fileExists = FileManager.default.fileExists(atPath: url.path)
            stateInfo["exists"] = fileExists

            if fileExists {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

                    if let modificationDate = attributes[.modificationDate] as? Date {
                        stateInfo["modificationDate"] = modificationDate.timeIntervalSince1970
                    }

                    if let fileSize = attributes[.size] as? Int64 {
                        stateInfo["fileSize"] = fileSize
                    }

                    if let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
                        stateInfo["hasConflicts"] = !conflictVersions.isEmpty
                        stateInfo["conflictCount"] = conflictVersions.count

                        let conflictDates = conflictVersions.compactMap { $0.modificationDate?.timeIntervalSince1970 }
                        if !conflictDates.isEmpty {
                            stateInfo["conflictDates"] = conflictDates
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                completion(stateInfo, nil)
            }
        }
    }

    /// Read a document in place using NSDocument coordination.
    func readInPlaceDocument(
        at url: URL,
        completion: @escaping (String?, Error?) -> Void
    ) {
        let document = ICloudInPlaceDocument()

        // NSDocument reads synchronously; run off the main thread and rely on
        // its default URL->data read chain (read(from:ofType:) -> read(from:Data:)).
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try document.read(from: url, ofType: "public.data")
                let contents = document.textContents
                DispatchQueue.main.async {
                    document.close()
                    completion(contents, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    document.close()
                    completion(nil, error)
                }
            }
        }
    }

    /// Write a document in place using NSDocument coordination.
    func writeInPlaceDocument(
        at url: URL,
        contents: String,
        completion: @escaping (Error?) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                let handled = try await CoordinatedReplaceWriter.live
                    .overwriteExistingItem(at: url) { replacementURL in
                        try writeTextToURL(contents, to: replacementURL)
                    }

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

            let document = ICloudInPlaceDocument()
            document.textContents = contents

            do {
                try document.write(
                    to: url,
                    ofType: "public.data",
                    for: .saveAsOperation,
                    originalContentsURL: nil
                )
                DispatchQueue.main.async {
                    document.close()
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    document.close()
                    completion(error)
                }
            }
        }
    }

    /// Read a binary document in place using NSDocument coordination.
    func readInPlaceBinaryDocument(
        at url: URL,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        let document = ICloudInPlaceBinaryDocument()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try document.read(from: url, ofType: "public.data")
                let contents = document.dataContents
                DispatchQueue.main.async {
                    document.close()
                    completion(contents, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    document.close()
                    completion(nil, error)
                }
            }
        }
    }

    /// Write a binary document in place using NSDocument coordination.
    func writeInPlaceBinaryDocument(
        at url: URL,
        contents: Data,
        completion: @escaping (Error?) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                let handled = try await CoordinatedReplaceWriter.live
                    .overwriteExistingItem(at: url) { replacementURL in
                        try writeDataToURL(contents, to: replacementURL)
                    }

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

            let document = ICloudInPlaceBinaryDocument()
            document.dataContents = contents

            do {
                try document.write(
                    to: url,
                    ofType: "public.data",
                    for: .saveAsOperation,
                    originalContentsURL: nil
                )
                DispatchQueue.main.async {
                    document.close()
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    document.close()
                    completion(error)
                }
            }
        }
    }
}
