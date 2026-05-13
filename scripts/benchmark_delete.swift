import Foundation

// Mock implementation of NSFileCoordinator delete operation for benchmarking
// Note: We can't easily mock the main thread blocking in a simple script without setup,
// but we can measure the time it takes.
func runBenchmark() {
    let fm = FileManager.default
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

    try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
    defer { try? fm.removeItem(at: tempDir) }

    let fileCount = 100
    for i in 0..<fileCount {
        let fileURL = tempDir.appendingPathComponent("file_\(i).txt")
        try? "test".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let startTime = CFAbsoluteTimeGetCurrent()

    for i in 0..<fileCount {
        let fileURL = tempDir.appendingPathComponent("file_\(i).txt")
        let coordinator = NSFileCoordinator(filePresenter: nil)

        var coordError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordError) { writeURL in
            try? fm.removeItem(at: writeURL)
        }
    }

    let endTime = CFAbsoluteTimeGetCurrent()
    let elapsedMS = (endTime - startTime) * 1000

    print("Baseline: \(elapsedMS) ms for \(fileCount) deletes")
}

// Swift command is not available in environment, so we won't run this, but we have it for explanation.
