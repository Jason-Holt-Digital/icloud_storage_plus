import Foundation

class MockItem: NSObject {}

let results: [Any] = (0..<100_000).map { _ in MockItem() }

func mapItem(_ item: MockItem, path: String) -> [String: Any?]? {
    return ["path": path]
}

func oldWay(results: [Any]) -> [[String: Any?]] {
    let casted = results.compactMap { $0 as? MockItem }
    var fileMaps: [[String: Any?]] = []
    let path = "some/path"
    for item in casted {
        if let map = mapItem(item, path: path) {
            fileMaps.append(map)
        }
    }
    return fileMaps
}

func newWay(results: [Any]) -> [[String: Any?]] {
    let path = "some/path"
    return results.compactMap { item -> [String: Any?]? in
        guard let mock = item as? MockItem else { return nil }
        return mapItem(mock, path: path)
    }
}

// Warm up
_ = oldWay(results: results)
_ = newWay(results: results)

let startOld = CFAbsoluteTimeGetCurrent()
for _ in 0..<10 {
    _ = oldWay(results: results)
}
let endOld = CFAbsoluteTimeGetCurrent()

let startNew = CFAbsoluteTimeGetCurrent()
for _ in 0..<10 {
    _ = newWay(results: results)
}
let endNew = CFAbsoluteTimeGetCurrent()

print("Old way: \(endOld - startOld)")
print("New way: \(endNew - startNew)")
