import Foundation

func testGetDocumentMetadataPerf() {
    let containerURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_container")
    try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

    let fileURL = containerURL.appendingPathComponent("test_file.txt")
    FileManager.default.createFile(atPath: fileURL.path, contents: Data([1,2,3]))

    let iterations = 1000

    // Warmup
    for _ in 0..<100 {
        _ = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
    }

    let start = CFAbsoluteTimeGetCurrent()

    for _ in 0..<iterations {
        _ = FileManager.default.fileExists(atPath: fileURL.path)
        let _ = try? fileURL.resourceValues(forKeys: [
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
        _ = containerURL.standardizedFileURL.path
    }

    let end = CFAbsoluteTimeGetCurrent()
    print("Time taken for \(iterations) synchronous file I/O operations: \(end - start) seconds")
}

testGetDocumentMetadataPerf()
