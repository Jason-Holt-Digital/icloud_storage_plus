import Foundation

struct PendingQueryItem {
    let url: URL
    let size: Any?
}

class FakeNSMetadataItem {
    var url: URL?
    init(url: URL?) { self.url = url }
}

let itemCount = 100_000
let items: [Any] = (0..<itemCount).map { i in
    FakeNSMetadataItem(url: URL(fileURLWithPath: "/tmp/\(i)"))
}

func extractPendingItem(from item: FakeNSMetadataItem) -> PendingQueryItem? {
    guard let url = item.url else { return nil }
    return PendingQueryItem(url: url, size: 100)
}

func mapPendingItem(_ item: PendingQueryItem, containerPath: String) -> [String: Any?] {
    return [
        "relativePath": item.url.path,
        "isDirectory": false,
        "sizeInBytes": item.size
    ]
}

func mapFileAttributesFromQuery_original(results: [Any], containerPath: String) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    let pendingItems = results.compactMap { item -> PendingQueryItem? in
      guard let fileItem = item as? FakeNSMetadataItem else { return nil }
      return extractPendingItem(from: fileItem)
    }
    for item in pendingItems {
      fileMaps.append(mapPendingItem(item, containerPath: containerPath))
    }
    return fileMaps
}

func mapFileAttributesFromQuery_optimized(results: [Any], containerPath: String) -> [[String: Any?]] {
    return results.compactMap { item -> [String: Any?]? in
      guard let fileItem = item as? FakeNSMetadataItem,
            let pendingItem = extractPendingItem(from: fileItem) else { return nil }
      return mapPendingItem(pendingItem, containerPath: containerPath)
    }
}

// Warmup
_ = mapFileAttributesFromQuery_original(results: items, containerPath: "/tmp")
_ = mapFileAttributesFromQuery_optimized(results: items, containerPath: "/tmp")

let iterations = 10

let startOriginal = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = mapFileAttributesFromQuery_original(results: items, containerPath: "/tmp")
}
let timeOriginal = CFAbsoluteTimeGetCurrent() - startOriginal

let startOptimized = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = mapFileAttributesFromQuery_optimized(results: items, containerPath: "/tmp")
}
let timeOptimized = CFAbsoluteTimeGetCurrent() - startOptimized

print("Performance comparison for mapFileAttributesFromQuery (100,000 items, 10 iterations):")
print("Original time: \(String(format: "%.4f", timeOriginal)) seconds")
print("Optimized time: \(String(format: "%.4f", timeOptimized)) seconds")
let improvement = (timeOriginal - timeOptimized) / timeOriginal * 100
print("Improvement: \(String(format: "%.2f", improvement))%")
