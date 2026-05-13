# Performance Optimization: Reduce Redundant Path Normalization in Loops

## Issue
The previous implementation of `relativePath(for:containerURL:)` calculated
`containerURL.standardizedFileURL.path` every time it was called.
`standardizedFileURL` performs in-memory URL/path normalization (for example,
removing `.` and `..` components). Even though each call is relatively cheap,
performing that work repeatedly in a tight loop is redundant.
This method was called inside a loop in `mapFileAttributesFromQuery`, which
iterates over all items in the iCloud container. For a container with $N$ items,
this resulted in $O(N)$ repeated normalizations just to re-calculate the same
constant container path.

## Optimization
We refactored the code to calculate `containerPath` once before the loop and
pass it down to `relativePath` (and intermediate mapping functions). This
changes the complexity of the container path standardization step from being
performed $O(N)$ times to $O(1)$ time per gather operation, while the overall
file listing remains $O(N)$ because `relativePath` is still computed for each
item.

## Performance Impact
This change reduces the *container path normalization* from $O(N)$ to $O(1)$ per
query gathering operation (the overall listing still performs $O(N)$ work per
item, including relative path computation).

The improvement is most relevant for large file lists, where shaving repeated
per-item work can reduce CPU time and allocations.

## iOS Micro-benchmark (optional)
If you want a rough sense of the overhead difference, you can run the following
Swift snippet in an Xcode Playground or as a standalone Swift file on macOS.

Note: this is a micro-benchmark of repeated path normalization and should not
be treated as a full end-to-end iCloud performance benchmark.

```swift
import Foundation

func relativePathOld(for fileURL: URL, containerURL: URL) -> String {
    let containerPath = containerURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(containerPath) else {
        return fileURL.lastPathComponent
    }
    var relative = String(filePath.dropFirst(containerPath.count))
    if relative.hasPrefix("/") {
        relative.removeFirst()
    }
    return relative
}

func relativePathNew(for fileURL: URL, containerPath: String) -> String {
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(containerPath) else {
        return fileURL.lastPathComponent
    }
    var relative = String(filePath.dropFirst(containerPath.count))
    if relative.hasPrefix("/") {
        relative.removeFirst()
    }
    return relative
}

let containerURL = URL(
    fileURLWithPath: "/Users/user/Library/Mobile Documents/iCloud~com~example~app/Documents/"
)
let fileURL = containerURL.appendingPathComponent("folder/file.txt")
let iterations = 100_000

let startOld = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = relativePathOld(for: fileURL, containerURL: containerURL)
}
let endOld = CFAbsoluteTimeGetCurrent()
print("Old implementation time: \\(endOld - startOld) seconds")

let startNew = CFAbsoluteTimeGetCurrent()
let containerPath = containerURL.standardizedFileURL.path
for _ in 0..<iterations {
    _ = relativePathNew(for: fileURL, containerPath: containerPath)
}
let endNew = CFAbsoluteTimeGetCurrent()
print("New implementation time: \\(endNew - startNew) seconds")
```

## Additional Optimization: Tight Loop Efficiency in `listContents`

In the `listContents` method on both iOS and macOS, redundant work inside the
directory-enumeration loop was removed:

1. `Set(keys)` is created once before the loop instead of on every item.
2. The parent-relative path for the listed directory is calculated once before
   iterating children.
3. Hidden-file filtering now happens before `resourceValues(forKeys:)`, so
   hidden files do not pay the metadata lookup cost.

## Affected Methods
- `relativePath(for:containerURL:)` -> `relativePath(for:containerPath:)`
- `mapMetadataItem(_:containerURL:)` -> `mapMetadataItem(_:containerPath:)`
- `mapResourceValues(fileURL:values:containerURL:)` -> `mapResourceValues(fileURL:values:containerPath:)`
- `mapFileAttributesFromQuery(query:containerURL:)` (Implementation updated)
- `getDocumentMetadata` (Implementation updated)
- `listContents` (Loop optimized in both iOS and macOS plugins)

## Performance Optimization: Non-blocking NSFileCoordinator operations

## Issue
Synchronous operations such as `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)` block the thread they are called on while waiting for access to the specified file. When called on the MainActor (main thread), this can lead to UI stutters or complete freezes, especially if the file is being downloaded from iCloud, is locked by another process, or involves high I/O latency.

In our case, the `delete` method was executing its file coordination block directly on the main thread, leading to potential UI blocking.

## Optimization
We moved the `NSFileCoordinator` invocation and the actual file removal operation to a background queue (`DispatchQueue.global(qos: .userInitiated)`). The `FlutterResult` callback is then dispatched back to the main queue to ensure thread safety when communicating with the Flutter framework.

## Performance Impact
This optimization reduces the main thread block time from the latency of file coordination + I/O operation (which could be hundreds of milliseconds or even seconds in case of iCloud synchronization waits) to approximately 0 ms (just the dispatch overhead). This vastly improves the responsiveness of the Flutter application's UI when initiating file deletions.

## Micro-benchmark (optional)
To demonstrate the UI unblocking effect, here is a conceptual Swift snippet that simulates file coordination blocking.

```swift
import Foundation

func performDeleteSynchronously(fileURL: URL, completion: @escaping () -> Void) {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    // Blocks the current thread
    coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: nil) { url in
        // Simulate I/O latency
        Thread.sleep(forTimeInterval: 0.5)
        completion()
    }
}

func performDeleteAsynchronously(fileURL: URL, completion: @escaping () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: nil) { url in
            // Simulate I/O latency
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

// In a UI application, calling performDeleteSynchronously would freeze the UI for > 0.5 seconds.
// Calling performDeleteAsynchronously returns immediately, allowing 60fps scrolling to continue.
```

## Affected Methods
- `delete` (in both iOS and macOS plugins)
