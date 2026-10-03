import AppKit
import CoreFoundation
import Foundation

/// Session-only binding. Restarting never restores a document or imports a task.
struct WikiOSReturnPreview: Equatable, Identifiable {
    let id = UUID()
    let request: QiWorkRequestFile
    let text: String
    let sourceName: String
    let sourceRevision: UInt64
}

enum WikiOSExchangeReview: Identifiable {
    case incoming(QiWorkRequestFile)
    case outgoing(WikiOSReturnPreview)
    var id: String {
        switch self {
        case .incoming(let file): "incoming-" + file.id
        case .outgoing(let preview): "outgoing-" + preview.id.uuidString
        }
    }
}

enum WikiOSTaskExchangeError: LocalizedError {
    case busy(String), changed, noTask, unavailable
    var errorDescription: String? {
        switch self {
        case .busy(let reason): reason
        case .changed: "Your working copy or task changed after this review opened. Review the current copy again."
        case .noTask: "Open a WikiOS task in this session before returning work."
        case .unavailable: "The installed WikiOS app does not support this exchange yet. Your saved result is available to open after WikiOS is updated."
        }
    }
}

/// Opens one known native application. A package cannot nominate an app, path,
/// URL, command, provider, or task mutation as its destination.
@MainActor
enum WikiOSExchangeDelivery {
    static var applicationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Quotient WikiOS.app", isDirectory: true)
    }
    static func validateApplication(_ url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { throw WikiOSTaskExchangeError.unavailable }
        let bytes = try QiWorkExchange.read(url.appendingPathComponent("Contents/Info.plist"))
        guard bytes.count <= 65_536,
              let info = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.quotient.wikios.native",
              let version = info["QiWorkExchangeVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 1,
              version.doubleValue == 1 else { throw WikiOSTaskExchangeError.unavailable }
    }
    static func open(_ file: QiWorkResultFile, completion: @escaping @MainActor (String?) -> Void) {
        do {
            try file.verifyUnchanged()
            try validateApplication(applicationURL)
        } catch { completion(error.localizedDescription); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([file.url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in completion(message) }
        }
    }
}
