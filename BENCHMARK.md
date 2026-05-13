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

# Performance Optimization: Asynchronous File Coordination

## Issue
In the `delete` method, `NSFileCoordinator` operations were being executed synchronously on the main thread because the calling context `resolveContainerURL` dispatches its completion handler on the `MainActor`. Synchronous filesystem operations, especially coordinated ones which involve IPC and locking, can block the main thread and cause UI freezing or hitches.

## Optimization
We moved the `NSFileCoordinator` operations inside `delete` to a background thread using `DispatchQueue.global(qos: .userInitiated).async`. The result is safely dispatched back to the main thread via `DispatchQueue.main.async` to ensure compatibility with Flutter channel expectations. This optimization was applied to both the iOS and macOS plugin implementations.

## Performance Impact
This change significantly improves main thread responsiveness by eliminating the UI block that previously occurred while waiting for the file coordinator lock and filesystem modification.

## Micro-benchmark Simulation
Since `NSFileCoordinator` blocking is highly dependent on system load and other processes accessing the same files, a micro-benchmark won't provide a consistent ms value. However, any operation taking >16ms on the main thread causes a dropped frame. By moving this file coordination (which typically takes several to tens of milliseconds) to a background thread, we avoid dropping frames and preserve a smooth 60fps UI.
