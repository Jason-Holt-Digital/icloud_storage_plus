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
Furthermore, the previous method still performed $O(N)$ runtime allocations and computations
inside the loop to determine `hasSuffix("/")`, string concatenation (`+ "/"`),
and `.count` computations for the `containerPath`.

## Optimization
We refactored the code to calculate `containerPath`, its normalized variant (with a trailing slash),
and their respective lengths *once* before the loop inside a `ContainerPathInfo` struct. We then
pass this struct down to `relativePath` (and intermediate mapping functions). This
changes the complexity of all container path operations (standardization, normalization, counting)
from being performed $O(N)$ times to $O(1)$ time per gather operation, while the overall
file listing remains $O(N)$ because `relativePath` is still computed for each item.

## Performance Impact
This change reduces the *container path normalization and computation* from $O(N)$ to $O(1)$ per
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

struct ContainerPathInfo {
    let path: String
    let normalizedPath: String
    let pathLength: Int
    let normalizedPathLength: Int

    init(path: String) {
      self.path = path
      self.normalizedPath = path.hasSuffix("/") ? path : path + "/"
      self.pathLength = path.count
      self.normalizedPathLength = normalizedPath.count
    }
}

func relativePathOld(for fileURL: URL, containerPath: String) -> String {
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

func relativePathNew(for fileURL: URL, containerPathInfo: ContainerPathInfo) -> String {
    let filePath = fileURL.standardizedFileURL.path
    guard filePath == containerPathInfo.path || filePath.hasPrefix(containerPathInfo.normalizedPath) else {
      return fileURL.lastPathComponent
    }
    let prefixLength = filePath == containerPathInfo.path
      ? containerPathInfo.pathLength
      : containerPathInfo.normalizedPathLength
    var relative = String(filePath.dropFirst(prefixLength))
    if relative.hasPrefix("/") {
      relative.removeFirst()
    }
    return relative
}

let containerPath = "/Users/user/Library/Mobile Documents/iCloud~com~example~app/Documents"
let containerURL = URL(fileURLWithPath: containerPath)
let fileURL = containerURL.appendingPathComponent("folder/file.txt")
let iterations = 100_000

let startOld = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = relativePathOld(for: fileURL, containerPath: containerPath)
}
let endOld = CFAbsoluteTimeGetCurrent()
print("Old implementation time: \\(endOld - startOld) seconds")

let startNew = CFAbsoluteTimeGetCurrent()
let info = ContainerPathInfo(path: containerPath)
for _ in 0..<iterations {
    _ = relativePathNew(for: fileURL, containerPathInfo: info)
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
- `relativePath(for:containerPath:)` -> `relativePath(for:containerPathInfo:)`
- `mapMetadataItem(_:containerPath:)` -> `mapMetadataItem(_:containerPathInfo:)`
- `mapResourceValues(fileURL:values:containerPath:)` -> `mapResourceValues(fileURL:values:containerPathInfo:)`
- `mapFileAttributesFromQuery(query:containerURL:)` (Implementation updated)
- `getDocumentMetadata` (Implementation updated)
- `listContents` (Loop optimized in both iOS and macOS plugins)
