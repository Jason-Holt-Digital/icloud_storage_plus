# Performance Optimization: Combine filtering and mapping in NSMetadataQuery results

## Context
When processing the results of an `NSMetadataQuery` (which can contain thousands of items if a large directory is being observed), the code previously performed a redundant array allocation.

In `macOSICloudStoragePlugin.swift`, the code did this:
```swift
let results = query.results.compactMap { $0 as? NSMetadataItem }
let files = mapFileAttributes(items: results, containerURL: containerURL)
```
Where `mapFileAttributes` then iterated over the `results` array again.

In `iOSICloudStoragePlugin.swift`, the code did this:
```swift
let pendingItems = query.results.compactMap { item -> PendingQueryItem? in
  // ...
}
// ...
for item in pendingItems {
  fileMaps.append(mapPendingItem(item, containerPath: containerPath))
}
```

## Optimization
Both plugins were refactored to perform filtering, typecasting, and mapping within a single `.compactMap` loop over `query.results`.

```swift
// Refactored iOS example:
return query.results.compactMap { item -> [String: Any?]? in
  guard let fileItem = item as? NSMetadataItem else { return nil }
  guard let pendingItem = extractPendingItem(from: fileItem) else { return nil }
  return mapPendingItem(pendingItem, containerPath: containerPath)
}
```

## Performance Impact
By changing the implementation from two loops to one, we removed an intermediate array allocation of size $N$ (where $N$ is the number of files in the queried iCloud container).
While the time complexity remains $O(N)$, the constant factor for traversing the array is cut in half, and peak memory usage is reduced since the intermediate array of items (`results` or `pendingItems`) is no longer generated. This is highly beneficial for large iCloud containers, as mapping hundreds of thousands of files directly to the final `[[String: Any?]]` output skips a step of maintaining a large intermediate array and repeating the element access.

## Verification
No standalone Swift test execution is available on this environment since `swift` CLI isn't installed. However, the logic optimization leverages Swift's standard `compactMap` efficiency properties, reducing the Big-O spatial complexity overhead of the intermediate mapping by $O(N)$ references.
