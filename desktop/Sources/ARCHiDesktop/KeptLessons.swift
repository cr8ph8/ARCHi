import Foundation
import CryptoKit
import Darwin

/// An explicit user-selected task scope, never inferred from lesson text.
enum HamptonTaskScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case conversation, documentQuestion, passageRevision

    var id: String { rawValue }
    var title: String {
        switch self {
        case .conversation: "Chat"
        case .documentQuestion: "Reading documents"
        case .passageRevision: "Revising passages"
        }
    }
}

struct LessonSource: Codable, Equatable, Sendable {
    let name: String
    let digest: String

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 240 && name.utf8.count <= 960 && LessonValidation.isDigest(digest)
    }

    static func digest(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct LessonOrigin: Codable, Equatable, Sendable {
    let requestID: String
    let inputDigest: String

    var isValid: Bool { UUID(uuidString: requestID) != nil && LessonValidation.isDigest(inputDigest) }
}

/// Only an explicit user Keep creates this record. Generated text and model
/// confidence never promote a lesson. Source bindings contain no copied source.
struct KeptLesson: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var revision: UInt64
    var topic: String
    var text: String
    var reason: String
    var source: LessonSource?
    var origin: LessonOrigin?
    let createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var taskScope: HamptonTaskScope?

    init(id: String = UUID().uuidString, revision: UInt64 = 1, topic: String, text: String,
         reason: String = "", source: LessonSource? = nil, origin: LessonOrigin? = nil,
         createdAt: Date = Date(), updatedAt: Date? = nil, expiresAt: Date? = nil,
         taskScope: HamptonTaskScope? = nil) {
        self.id = id
        self.revision = revision
        self.topic = topic
        self.text = text
        self.reason = reason
        self.source = source
        self.origin = origin
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.expiresAt = expiresAt
        self.taskScope = taskScope
    }

    var isValid: Bool {
        LessonSnapshot(lesson: self).isValid
            && reason.count <= 300 && reason.utf8.count <= 1200
            && (origin?.isValid ?? true)
            && LessonValidation.isDate(createdAt) && LessonValidation.isDate(updatedAt)
            && updatedAt >= createdAt
            && (expiresAt.map { LessonValidation.isDate($0) && $0 > createdAt } ?? true)
    }

    /// Explicit task scope takes precedence over literal topic matching, while
    /// expiry and exact-source restrictions remain required for every lesson.
    func matches(question: String, sourceName: String?, sourceText: String, now: Date = Date(),
                 taskScope: HamptonTaskScope? = nil) -> Bool {
        guard isValid, LessonValidation.isDate(now), expiresAt.map({ $0 > now }) ?? true else { return false }
        if let source {
            guard source.name == sourceName, source.digest == LessonSource.digest(of: sourceText) else { return false }
        }
        if let savedScope = self.taskScope { return savedScope == taskScope }
        let topicWords = LessonValidation.words(topic)
        let questionWords = LessonValidation.words(question)
        guard !topicWords.isEmpty, questionWords.count >= topicWords.count else { return false }
        return (0...(questionWords.count - topicWords.count)).contains { offset in
            Array(questionWords[offset..<(offset + topicWords.count)]) == topicWords
        }
    }
}

/// An immutable copy captured when Send is pressed, independent of later edits.
struct LessonSnapshot: Codable, Equatable, Sendable {
    let id: String
    let revision: UInt64
    let topic: String
    let text: String
    let source: LessonSource?
    // Synthesized Codable omits nil, preserving legacy snapshot bytes/digests.
    let taskScope: HamptonTaskScope?

    init(id: String, revision: UInt64, topic: String, text: String, source: LessonSource? = nil,
         taskScope: HamptonTaskScope? = nil) {
        self.id = id
        self.revision = revision
        self.topic = topic
        self.text = text
        self.source = source
        self.taskScope = taskScope
    }

    init(lesson: KeptLesson) {
        self.init(id: lesson.id, revision: lesson.revision, topic: lesson.topic, text: lesson.text,
                  source: lesson.source, taskScope: lesson.taskScope)
    }

    var modelID: String { "kept-\(id)-r\(revision)" }
    var modelInput: JSONValue {
        var fields: [String: JSONValue] = ["id": .string(modelID), "text": .string(text), "topic": .string(topic),
                                           "kind": .string("user-confirmed-lesson")]
        if let taskScope { fields["taskScope"] = .string(taskScope.rawValue) }
        return .object(fields)
    }
    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0
            && (2...80).contains(topic.count) && topic.utf8.count <= 320
            && !LessonValidation.words(topic).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= 600 && text.utf8.count <= 2400
            && (source?.isValid ?? true)
    }
}

private enum LessonValidation {
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func isDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date > .distantPast && date < .distantFuture
    }
}

/// A versioned extension of the existing native preference file, not another
/// memory database. Preferences and explicitly kept lessons can be forgotten separately.
struct NativePreferenceDocument: Codable, Equatable {
    static let currentSchema = "archi-native-preferences/v8"
    private static let previousSchemas = ["archi-native-preferences/v2", "archi-native-preferences/v3", "archi-native-preferences/v4", "archi-native-preferences/v5", "archi-native-preferences/v6", "archi-native-preferences/v7"]
    static let maximumBytes = 64 * 1024
    static let maximumLessons = 16
    var schema = Self.currentSchema
    var revision: UInt64 = 0
    var preferences: CompanionPreferences? = nil
    var lessons: [KeptLesson] = []
    var focusGesture: FocusGestureConfiguration? = nil
    var qiMon: LocalQiMon? = nil
    var itemLibrary: [CompanionItemPackage] = []
    var personalContext: PersonalContext? = nil

    static func validateLessonSnapshots(_ snapshots: [LessonSnapshot]) -> Bool {
        snapshots.count <= maximumLessons && snapshots.allSatisfy(\.isValid)
            && Set(snapshots.compactMap { UUID(uuidString: $0.id) }).count == snapshots.count
    }

    var isValid: Bool {
        schema == Self.currentSchema && (preferences?.isValid ?? true)
            && (qiMon?.isValid ?? true)
            && (personalContext?.isValid ?? true)
            && CompanionItemPackage.isValidLibrary(itemLibrary)
            && (preferences?.equipment.design.map { itemLibrary.contains($0) } ?? true)
            && lessons.allSatisfy(\.isValid)
            && Self.validateLessonSnapshots(lessons.map(LessonSnapshot.init(lesson:)))
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw NativePreferenceError.tooLarge }
        var scanner = NativePreferenceJSONKeys(bytes: Array(data))
        try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativePreferenceError.invalidDocument
        }
        let document: Self
        if object.keys.contains("schema") {
            guard let schema = object["schema"] as? String,
                  schema == currentSchema || previousSchemas.contains(schema) else { throw NativePreferenceError.unsupportedSchema }
            let optional: Set<String> = (schema == currentSchema || schema == "archi-native-preferences/v7" || schema == "archi-native-preferences/v6") ? ["preferences", "focusGesture", "qiMon", "itemLibrary", "personalContext"]
                : schema == "archi-native-preferences/v5" ? ["preferences", "focusGesture", "qiMon", "itemLibrary"]
                : schema == "archi-native-preferences/v4" ? ["preferences", "focusGesture", "qiMon"]
                : schema == "archi-native-preferences/v3" ? ["preferences", "focusGesture"] : ["preferences"]
            try validateKeys(object, required: ["schema", "revision", "lessons"], optional: optional)
            if let preferences = object["preferences"], !(preferences is NSNull) {
                guard let fields = preferences as? [String: Any] else { throw NativePreferenceError.invalidDocument }
                try validatePreferenceKeys(fields)
            }
            if let focusGesture = object["focusGesture"], !(focusGesture is NSNull) {
                guard let fields = focusGesture as? [String: Any] else { throw NativePreferenceError.invalidDocument }
                try validateKeys(fields, required: ["pace", "sparkle", "hold"])
            }
            if let qiMon = object["qiMon"], !(qiMon is NSNull) {
                guard let fields = qiMon as? [String: Any] else { throw NativePreferenceError.invalidDocument }
                try validateKeys(fields, required: ["character", "originDigest", "welcomedAt"])
            }
            if let context = object["personalContext"], !(context is NSNull) {
                guard let fields = context as? [String: Any], let entries = fields["entries"] as? [[String: Any]] else { throw NativePreferenceError.invalidDocument }
                try validateKeys(fields, required: ["version", "revision", "name", "preferredName", "entries"])
                for entry in entries { try validateKeys(entry, required: ["id", "title", "text", "status", "source", "useInAssistance"]) }
            }
            guard let lessons = object["lessons"] as? [[String: Any]] else { throw NativePreferenceError.invalidDocument }
            for lesson in lessons {
                try validateKeys(lesson, required: ["id", "revision", "topic", "text", "reason", "createdAt", "updatedAt"],
                    optional: schema == currentSchema ? ["source", "origin", "expiresAt", "taskScope"] : ["source", "origin", "expiresAt"])
                for (key, required) in [("source", Set(["name", "digest"])), ("origin", Set(["requestID", "inputDigest"]))] {
                    if let value = lesson[key], !(value is NSNull) {
                        guard let fields = value as? [String: Any] else { throw NativePreferenceError.invalidDocument }
                        try validateKeys(fields, required: required)
                    }
                }
            }
            var decoded = try JSONDecoder().decode(Self.self, from: data)
            // Loading a known older envelope migrates in memory only. Its exact
            // bytes remain the write-conflict baseline until an explicit save.
            decoded.schema = currentSchema
            document = decoded
        } else {
            // Only the known bare preference shape migrates. An envelope missing
            // its schema must not silently shed lessons or an unknown version.
            try validatePreferenceKeys(object)
            let old = try JSONDecoder().decode(CompanionPreferences.self, from: data)
            document = Self(preferences: old)
        }
        guard document.isValid else { throw NativePreferenceError.invalidDocument }
        return document
    }

    func encoded() throws -> Data {
        guard isValid else { throw NativePreferenceError.invalidDocument }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw NativePreferenceError.tooLarge }
        return data
    }

    private static func validatePreferenceKeys(_ object: [String: Any]) throws {
        try validateKeys(object, required: ["form", "tone", "replyLength", "size", "adaptive", "reduceMotion", "quiet"],
                         optional: ["workspaceAppearance", "seedAppearance", "seedColor", "visualTreatment", "equipment", "musicalCues", "musicalVolume"])
    }

    private static func validateKeys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
        let keys = Set(object.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
            throw NativePreferenceError.invalidDocument
        }
    }
}

extension NativePreferenceDocument {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        revision = try values.decode(UInt64.self, forKey: .revision)
        preferences = try values.decodeIfPresent(CompanionPreferences.self, forKey: .preferences)
        lessons = try values.decode([KeptLesson].self, forKey: .lessons)
        focusGesture = try values.decodeIfPresent(FocusGestureConfiguration.self, forKey: .focusGesture)
        qiMon = try values.decodeIfPresent(LocalQiMon.self, forKey: .qiMon)
        itemLibrary = try values.decodeIfPresent([CompanionItemPackage].self, forKey: .itemLibrary) ?? []
        personalContext = try values.decodeIfPresent(PersonalContext.self, forKey: .personalContext)
    }
}

enum NativePreferenceError: LocalizedError {
    case invalidDocument, unsupportedSchema, tooLarge, conflict, invalidLocation
    var errorDescription: String? {
        switch self {
        case .invalidDocument: "The saved preferences or lessons are invalid. The previous save has been preserved."
        case .unsupportedSchema: "This preference file uses an unsupported version. It has been preserved."
        case .tooLarge: "The native preference file exceeds the 64 KB limit."
        case .conflict: "The saved preferences changed outside this session. Reload before saving."
        case .invalidLocation: "The preference location must be a regular local file."
        }
    }
}

enum NativePreferencePersistence {
    static func read(_ url: URL) throws -> (document: NativePreferenceDocument, baseline: Data?) {
        guard let data = try rawData(at: url) else { return (NativePreferenceDocument(), nil) }
        return (try NativePreferenceDocument.decode(data), data)
    }

    /// Compare the exact loaded bytes before writing and again immediately before
    /// replacement. Existing state is published by the caller only after success.
    /// This detects external edits; it is not a cross-process database transaction.
    @discardableResult
    static func write(document: NativePreferenceDocument, to url: URL, expected: Data?) throws -> Data? {
        let data = try document.encoded()
        guard try rawData(at: url) == expected else { throw NativePreferenceError.conflict }
        if document.preferences == nil && document.lessons.isEmpty && document.focusGesture == nil && document.qiMon == nil && document.itemLibrary.isEmpty && document.personalContext == nil {
            if expected != nil { try FileManager.default.removeItem(at: url) }
            return nil
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        guard descriptor >= 0 else { throw posixError() }
        var isOpen = true
        defer {
            if isOpen { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        guard Darwin.close(descriptor) == 0 else { isOpen = false; throw posixError() }
        isOpen = false
        guard try rawData(at: url) == expected else { throw NativePreferenceError.conflict }
        let replaced = temporary.path.withCString { source in url.path.withCString { target in Darwin.rename(source, target) } }
        guard replaced == 0 else { throw posixError() }
        return data
    }

    private static func rawData(at url: URL) throws -> Data? {
        guard url.isFileURL else { throw NativePreferenceError.invalidLocation }
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        if result != 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw NativePreferenceError.invalidLocation }
        guard info.st_size <= NativePreferenceDocument.maximumBytes else { throw NativePreferenceError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= NativePreferenceDocument.maximumBytes else { throw NativePreferenceError.tooLarge }
        return data
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

/// Detect duplicate keys before Foundation can silently collapse them. This
/// bounded lexical pass follows the existing native evolution save contract.
private struct NativePreferenceJSONKeys {
    let bytes: [UInt8]
    private var index = 0
    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func validate() throws {
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw NativePreferenceError.invalidDocument }
    }

    private mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 8, index < bytes.count else { throw NativePreferenceError.invalidDocument }
        switch bytes[index] {
        case 123:
            index += 1
            whitespace()
            if take(125) { return }
            var keys = Set<String>()
            while true {
                whitespace()
                let key = try string()
                guard keys.insert(key).inserted else { throw NativePreferenceError.invalidDocument }
                whitespace()
                guard take(58) else { throw NativePreferenceError.invalidDocument }
                try value(depth: depth + 1)
                whitespace()
                if take(125) { return }
                guard take(44) else { throw NativePreferenceError.invalidDocument }
            }
        case 91:
            index += 1
            whitespace()
            if take(93) { return }
            while true {
                try value(depth: depth + 1)
                whitespace()
                if take(93) { return }
                guard take(44) else { throw NativePreferenceError.invalidDocument }
            }
        case 34: _ = try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw NativePreferenceError.invalidDocument }
        }
    }

    private mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw NativePreferenceError.invalidDocument }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 {
                guard index < bytes.count else { throw NativePreferenceError.invalidDocument }
                index += 1
            } else if byte < 32 { throw NativePreferenceError.invalidDocument }
        }
        throw NativePreferenceError.invalidDocument
    }

    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
