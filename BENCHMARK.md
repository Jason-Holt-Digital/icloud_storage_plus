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

## Performance Optimization: Non-blocking iCloud Downloads

## Issue
The call to `FileManager.default.startDownloadingUbiquitousItem(at:)` performs synchronous file system operations and inter-process communication. In multiple paths (`downloadFile`, `readInPlace`, `readInPlaceBytes`, and write entrypoints), this was being executed directly on the `@MainActor`. As a result, initiating an iCloud file download would block the main thread, leading to potential UI hitches and frame drops in the Flutter application.

## Optimization
We wrapped the `startDownloadingUbiquitousItem` calls inside a detached background task:
```swift
try await Task.detached(priority: .userInitiated) {
    try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
}.value
```
This offloads the synchronous blocking call to a background thread while maintaining the required `@MainActor` isolation and asynchronous control flow for the rest of the file coordination logic.

## Performance Impact
Moving `startDownloadingUbiquitousItem(at:)` off the main thread completely eliminates UI blocking when initiating downloads. While the overall download time is identical, this significantly improves application responsiveness and frame rate during heavy file synchronization operations, especially when triggering downloads for multiple files simultaneously or when the underlying IPC to the daemon introduces latency.

## Affected Methods
- `downloadFile` (iOS & macOS plugins)
- `readInPlace` (iOS & macOS plugins)
- `readInPlaceBytes` (iOS & macOS plugins)
- `liveEnsureDownloaded` (in `CoordinatedReplaceWriter.swift` for both platforms)
