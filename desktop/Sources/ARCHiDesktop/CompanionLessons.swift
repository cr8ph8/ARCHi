import Foundation

/// A reviewable user draft. Editing it has no persistence or model side effects.
struct LessonCorrectionDraft: Identifiable, Equatable {
    let id = UUID()
    var lessonID: String?
    let expectedRevision: UInt64
    let prior: KeptLesson?
    var topic = ""
    var text = ""
    var reason = ""
    var source: LessonSource?
    var origin: LessonOrigin?
    var expiresAt: Date?
    var taskScope: HamptonTaskScope? = nil
}
