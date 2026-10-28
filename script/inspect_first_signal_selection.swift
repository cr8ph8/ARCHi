// Read-only selection evidence. Never launch WebKit, inspect a save, refresh a
// bookmark, or write UserDefaults. Keep these pins aligned with the host.
import CryptoKit
import Foundation

let suite = "com.quotient.archi.qimon-local-play"
let owner: [String: String] = [
    "appIdentifier": "com.quotient.archi.desktop.review",
    "origin": "http://127.0.0.1:8767/",
    "dataStoreID": "A4A19A25-351B-45B6-9D70-3B15D0A02817",
    "saveKey": "qimon.first-signal.chapter.v1",
    "defaultsSuite": suite,
    "selectionKey": "selectedEmbeddedFolder.v1",
]

func selection(_ defaults: UserDefaults, key: String) throws -> [String: Any] {
    guard let value = defaults.object(forKey: key) else { return ["present": false] }
    guard let data = value as? Data else { throw InspectionError.invalidBookmark }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard url.isFileURL else { throw InspectionError.invalidBookmark }
    return ["present": true, "stale": stale,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "path": url.standardizedFileURL.path]
}

enum InspectionError: Error { case unavailableDefaults, invalidBookmark }
do {
    guard CommandLine.arguments.count == 1, let defaults = UserDefaults(suiteName: suite) else {
        throw InspectionError.unavailableDefaults
    }
    let value: [String: Any] = ["schema": "archi-first-signal-selection/v1", "owner": owner,
        "chapter": try selection(defaults, key: "selectedEmbeddedFolder.v1"),
        "earlierAdventure": try selection(defaults, key: "selectedGameBookmark.v1")]
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(bytes)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("First Signal selection could not be inspected without changing it. No selection or save was written.\n".utf8))
    exit(1)
}
