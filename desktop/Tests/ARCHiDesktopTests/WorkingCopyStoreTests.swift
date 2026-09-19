import AppKit
import Combine
import Testing
@testable import ARCHiDesktop

@MainActor
struct WorkingCopyStoreTests {
    @Test func procedureCannotReuseAnExternallyWithdrawnSupportingLesson() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        rig.store.beginLessonCorrection()
        var draft = try #require(rig.store.lessonDraft)
        draft.topic = "selected passage"; draft.text = "Use plain words."
        #expect(rig.store.keepLesson(draft))
        try await rig.begin()
        let lesson = try #require(rig.local.request?.localLessons.first)
        let proposal = try rig.local.complete(replacement: "Clear copy.", memoryIDs: [lesson.modelID])
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        let origin = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.reviewDocument(id: origin.id, verdict: .helpful))
        #expect(rig.store.keepDocumentProcedure(recordID: origin.id, title: "Plain words", instruction: "Use plain words."))
        let procedure = try #require(rig.store.documentProcedures.procedures.first)
        #expect(rig.store.documentProcedureUnavailable(procedure.binding) == nil)
        let other = CompanionStore(preferenceURL: rig.directory.appendingPathComponent("preferences.json"), assistant: RevisionStoreClient())
        #expect(other.withdrawLesson(id: lesson.id, expectedRevision: other.lessonRevision))
        #expect(!rig.store.keptLessons.isEmpty, "The old session still holds cached lesson data")
        #expect(rig.store.documentProcedureUnavailable(procedure.binding) != nil, "Fresh disk evidence must override cached eligibility")
        #expect(!rig.store.keepDocumentProcedure(recordID: origin.id, title: "Stale", instruction: "Use plain words."))
    }

    @Test func procedureReuseCapturesVersionAndCorrectionCannotBeErased() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let first = try rig.local.complete(replacement: "Clear copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: first.target.id)
        let origin = try #require(rig.store.documentWork.records.first)
        #expect(!rig.store.keepDocumentProcedure(recordID: origin.id, title: "Clear prose", instruction: "Use plain language."))
        #expect(rig.store.reviewDocument(id: origin.id, verdict: .helpful))
        #expect(rig.store.keepDocumentProcedure(recordID: origin.id, title: "Clear prose", instruction: "Use plain language."))
        let procedure = try #require(rig.store.documentProcedures.procedures.first)
        rig.store.share(text: "A different passage.", name: "second.txt")
        rig.store.selectText(range: NSRange(location: 0, length: rig.store.sharedText.utf16.count), sourceRevision: rig.store.sourceRevision)
        rig.store.preparePassageRevision()
        #expect(rig.store.prepareDocumentProcedure(procedure.binding))
        #expect(!rig.store.isWorking, "Preparing never sends or applies")
        rig.local.request = nil
        rig.store.submit()
        try await rig.wait { rig.local.request != nil }
        #expect(rig.local.request?.prompt == procedure.instruction)
        #expect(rig.store.documentWork.records.first?.procedureUse == procedure.binding)
        let second = try rig.local.complete(replacement: "Different clear passage.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: second.target.id)
        let reused = try #require(rig.store.documentWork.records.first)
        #expect(reused.state == .applied)
        #expect(rig.store.reviewDocument(id: reused.id, verdict: .needsCorrection))
        #expect(rig.store.documentWork.records.first?.procedureUseRejected == true)
        #expect(rig.store.reviewDocument(id: reused.id, verdict: .helpful))
        #expect(rig.store.documentProcedureUnavailable(procedure.binding) != nil)
        let reopened = CompanionStore(preferenceURL: rig.directory.appendingPathComponent("preferences.json"), assistant: RevisionStoreClient())
        #expect(reopened.documentProcedures.procedures.count == 1)
        #expect(reopened.documentProcedureUnavailable(procedure.binding) != nil)
        #expect(reopened.documentWork.records.first?.procedureUse == procedure.binding)
    }

    @Test func changedProcedureDraftCannotSendAndWithdrawnDependencyCannotApply() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let first = try rig.local.complete(replacement: "Clear copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: first.target.id)
        let origin = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.reviewDocument(id: origin.id, verdict: .helpful))
        #expect(rig.store.keepDocumentProcedure(recordID: origin.id, title: "Clear prose", instruction: "Use plain language."))
        let procedure = try #require(rig.store.documentProcedures.procedures.first)
        rig.store.share(text: "Another copy.", name: "new.txt")
        rig.store.selectText(range: NSRange(location: 0, length: rig.store.sharedText.utf16.count), sourceRevision: rig.store.sourceRevision)
        rig.store.preparePassageRevision()
        #expect(rig.store.prepareDocumentProcedure(procedure.binding))
        rig.store.requestsRevision = false
        rig.local.request = nil
        rig.store.submit()
        #expect(!rig.store.isWorking, "Ask mode cannot strip a prepared procedure’s admission checks")
        #expect(rig.local.request == nil)
        rig.store.requestsRevision = true
        rig.store.prompt = "A changed instruction."
        rig.local.request = nil
        rig.store.submit()
        #expect(!rig.store.isWorking)
        #expect(rig.local.request == nil)
        #expect(rig.store.prepareDocumentProcedure(procedure.binding))
        rig.store.submit()
        try await rig.wait { rig.local.request != nil }
        let second = try rig.local.complete(replacement: "Clearer copy.")
        try await rig.wait { !rig.store.isWorking }
        #expect(rig.store.canApplyDocumentRevision(provider: .qwen, proposal: second))
        #expect(rig.store.reviewDocument(id: origin.id, verdict: .withdrawn))
        #expect(!rig.store.canApplyDocumentRevision(provider: .qwen, proposal: second))
        rig.store.applyPassageRevision(provider: .qwen, targetID: second.target.id)
        #expect(rig.store.sharedText == "Another copy.")
    }

    @Test func applyTargetsExactOccurrenceAndUndoRestoresExactUnicodeBytes() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        let original = "Café 👩🏽‍💻. Repeat. Repeat. e\u{301}\r\n"
        let range = (original as NSString).range(of: "Repeat.", options: .backwards)
        try await rig.begin(text: original, range: range)
        let proposal = try rig.local.complete(replacement: "Revised!")
        try await rig.wait { rig.store.compareResults[.qwen]?.state == .complete }
        #expect(rig.store.sharedText == original, "Receiving a candidate cannot apply it")
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.sharedText == "Café 👩🏽‍💻. Repeat. Revised! e\u{301}\r\n")
        #expect(rig.store.canUndoWorkingCopyEdit)
        #expect(rig.store.documentWork.records.first?.state == .applied)
        #expect(rig.store.documentWork.records.first?.actualAfterDigest == WorkingCopyEditReceipt.digest(rig.store.sharedText))
        let applied = rig.store.sharedText, revision = rig.store.sourceRevision
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.sharedText == applied)
        #expect(rig.store.sourceRevision == revision)
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText.utf8.elementsEqual(original.utf8))
        #expect(rig.store.sourceRevision == revision + 1)
        #expect(!rig.store.canUndoWorkingCopyEdit)
        #expect(rig.store.documentWork.records.first?.state == .undone)
        #expect(!rig.store.companionGraphSnapshot().nodes.filter { $0.title == "Document revision" }.isEmpty)
    }

    @Test func appliedFeedbackSurvivesReplyClearingAndReversalCannotReturnThroughEvolutionLoad() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        let row = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.compareResults.isEmpty)
        #expect(row.learning?.requestBinding.isValid == true)
        #expect(row.feedback == nil)
        #expect(rig.store.evolution.usefulReceipts.isEmpty)
        #expect(rig.store.reviewDocument(id: row.id, verdict: .helpful))
        let event = try #require(rig.store.documentWork.records.first?.feedback)
        #expect(rig.store.reviewDocument(id: row.id, verdict: .helpful))
        #expect(rig.store.documentWork.records.first?.feedback?.id == event.id)
        #expect(rig.store.tokenSteward.tasks.first?.outcomes.count == 1)
        #expect(rig.store.tokenSteward.tasks.first?.userUseful == true)
        #expect(rig.store.evolution.usefulReceipts.isEmpty, "Feedback alone does not promote learning")
        #expect(rig.store.addDocumentToLearningReview(id: row.id))
        #expect(rig.store.addDocumentToLearningReview(id: row.id))
        #expect(rig.store.evolution.usefulReceipts.count == 1)
        #expect(rig.store.evolution.save())
        #expect(rig.store.reviewDocument(id: row.id, verdict: .needsCorrection))
        #expect(rig.store.tokenSteward.tasks.first?.userUseful == false)
        #expect(rig.store.evolution.usefulReceipts.isEmpty)
        #expect(rig.store.evolution.load())
        #expect(rig.store.evolution.usefulReceipts.isEmpty, "An older saved positive cannot overrule a durable correction")
        #expect(!rig.store.addDocumentToLearningReview(id: row.id))
        let reopened = DocumentWorkJournal(url: rig.directory.appendingPathComponent("preferences.document-work.json"))
        #expect(reopened.records.first?.feedback?.verdict == .needsCorrection)
        #expect(reopened.records.first?.learning == row.learning)
        #expect(rig.store.documentFeedbackUsageCurrent(try #require(rig.store.documentWork.records.first)))
    }

    @Test func correctionRequiresExplicitKeepAndUsedLessonMustStillMatch() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        rig.store.beginLessonCorrection()
        var draft = try #require(rig.store.lessonDraft)
        draft.topic = "selected passage"; draft.text = "Use clear language."
        #expect(rig.store.keepLesson(draft))
        try await rig.begin()
        let lesson = try #require(rig.local.request?.localLessons.first)
        let proposal = try rig.local.complete(replacement: "Revised copy.", memoryIDs: [lesson.modelID])
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        let row = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.reviewDocument(id: row.id, verdict: .helpful))
        #expect(rig.store.documentReviewLessons(row) == [lesson])
        #expect(rig.store.addDocumentToLearningReview(id: row.id, lesson: lesson))
        #expect(rig.store.evolution.usefulReceipts.first?.lessonUse?.matches(snapshot: lesson) == true)
        #expect(rig.store.withdrawLesson(id: lesson.id, expectedRevision: rig.store.lessonRevision))
        #expect(rig.store.documentReviewLessons(row).isEmpty)
        #expect(!rig.store.addDocumentToLearningReview(id: row.id, lesson: lesson))
        rig.store.beginDocumentCorrection(id: row.id)
        let correction = try #require(rig.store.lessonDraft)
        #expect(correction.origin?.requestID == row.requestID)
        #expect(correction.origin?.inputDigest == row.learning?.requestBinding.inputDigest)
        #expect(correction.text.isEmpty)
        #expect(rig.store.keptLessons.isEmpty, "Opening a correction does not invent or keep a lesson")
        rig.store.lessonDraft?.text = "My unfinished guidance."
        rig.store.beginDocumentCorrection(id: row.id)
        #expect(rig.store.lessonDraft?.text == "My unfinished guidance.")
        #expect(rig.store.lessonDraft?.origin == correction.origin)
    }

    @Test func interruptedUndoAllowsExistingFeedbackSyncAndWithdrawalOnly() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        var row = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.reviewDocument(id: row.id, verdict: .helpful))
        #expect(rig.store.addDocumentToLearningReview(id: row.id))
        #expect(rig.store.evolution.save())
        row = try #require(rig.store.documentWork.records.first)
        row.state = .undoing
        row.updatedAt = Date()
        try rig.store.documentWork.save(row)
        let reopened = CompanionStore(preferenceURL: rig.directory.appendingPathComponent("preferences.json"),
            assistant: RevisionStoreClient(), tokenSteward: rig.store.tokenSteward)
        let uncertain = try #require(reopened.documentWork.records.first)
        #expect(uncertain.state == .failed)
        #expect(!reopened.canReviewDocument(uncertain))
        #expect(reopened.canManageDocumentFeedback(uncertain))
        reopened.syncDocumentFeedback(id: row.id)
        #expect(reopened.documentFeedbackUsageCurrent(uncertain))
        #expect(!reopened.reviewDocument(id: row.id, verdict: .helpful))
        #expect(!reopened.addDocumentToLearningReview(id: row.id))
        #expect(reopened.evolution.load())
        reopened.withdrawLearningReview(requestID: try #require(UUID(uuidString: row.requestID)))
        #expect(reopened.documentWork.records.first?.feedback?.verdict == .withdrawn)
        #expect(reopened.tokenSteward.tasks.first?.userUseful == false)
        #expect(reopened.evolution.usefulReceipts.isEmpty)
        #expect(reopened.evolution.load())
        #expect(reopened.evolution.usefulReceipts.isEmpty)
    }

    @Test func unreadableFeedbackHistoryCannotRestoreOldPositiveLearning() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        let row = try #require(rig.store.documentWork.records.first)
        #expect(rig.store.reviewDocument(id: row.id, verdict: .helpful))
        #expect(rig.store.addDocumentToLearningReview(id: row.id))
        #expect(rig.store.evolution.save())
        #expect(rig.store.reviewDocument(id: row.id, verdict: .withdrawn))
        let journalURL = rig.directory.appendingPathComponent("preferences.document-work.json")
        let broken = Data("unreadable fixture".utf8)
        try broken.write(to: journalURL)
        let reopened = CompanionStore(preferenceURL: rig.directory.appendingPathComponent("preferences.json"),
            assistant: RevisionStoreClient(), tokenSteward: TokenStewardStore())
        #expect(reopened.documentWork.loadError != nil)
        let appearance = reopened.preferences
        #expect(!reopened.evolution.load())
        #expect(reopened.evolution.usefulReceipts.isEmpty)
        #expect(reopened.preferences == appearance)
        #expect(try Data(contentsOf: journalURL) == broken)
    }

    @Test func feedbackRetriesAndWithdrawalRemainDistinctFromMechanicalChecks() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        let pending = try #require(rig.store.documentWork.records.first)
        #expect(!rig.store.reviewDocument(id: pending.id, verdict: .helpful), "A preview is not an applied outcome")
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.reviewDocument(id: pending.id, verdict: .helpful))
        let record = try #require(rig.store.documentWork.records.first)
        rig.store.syncDocumentFeedback(id: record.id)
        rig.store.syncDocumentFeedback(id: record.id)
        #expect(rig.store.tokenSteward.tasks.first?.outcomes.count == 1)
        #expect(rig.store.tokenSteward.tasks.first?.outcomes.first?.kind == .userUseful)
        rig.store.withdrawLearningReview(requestID: try #require(UUID(uuidString: record.requestID)))
        #expect(rig.store.documentWork.records.first?.feedback?.verdict == .withdrawn)
        #expect(rig.store.tokenSteward.tasks.first?.userUseful == false)
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.documentWork.records.first?.state == .undone)
        #expect(rig.store.documentWork.records.first?.feedback?.verdict == .withdrawn)
    }

    @Test func receiptFailureDisablesUndoUntilExactPendingReceiptCanBeRetried() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        let url = rig.directory.appendingPathComponent("preferences.document-work.json")
        var pendingBytes: Data?
        let subscription = rig.store.$sharedText.dropFirst().sink { text in
            if text == "Revised copy." {
                // Inject a competing disk write after the pending Apply was
                // persisted, at the synchronous working-copy mutation boundary.
                pendingBytes = try? Data(contentsOf: url)
                try? Data("unreadable journal".utf8).write(to: url)
            }
        }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        subscription.cancel()
        #expect(rig.store.sharedText == "Revised copy.")
        #expect(rig.store.pendingDocumentReceipt?.state == .applied)
        #expect(!rig.store.canUndoWorkingCopyEdit)
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText == "Revised copy.")
        try #require(pendingBytes).write(to: url)
        rig.store.retryDocumentHistorySave()
        #expect(rig.store.pendingDocumentReceipt == nil)
        #expect(rig.store.canUndoWorkingCopyEdit)
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText == "Original copy.")
        #expect(rig.store.documentWork.records.first?.state == .undone)
    }

    @Test func failedConstraintCannotApplyAndUsageIsNotSemanticAcceptance() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin(text: "The meeting is at 12:30.")
        let proposal = try rig.local.complete(replacement: "Meet at 13:30.")
        try await rig.wait { !rig.store.isWorking }
        #expect(rig.store.documentWork.records.first?.state == .blocked)
        #expect(!rig.store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.sharedText == "The meeting is at 12:30.")
        #expect(!rig.store.canUndoWorkingCopyEdit)
        rig.store.dismissPassageRevision(provider: .qwen)
        #expect(rig.store.documentWork.records.first?.state == .dismissed)
    }

    @Test func compareCapturesSameTargetAndApplyCancelsUnfinishedSiblingAndLateOutput() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin(compare: true)
        let localRequest = try #require(rig.local.request)
        let cloudRequest = try #require(rig.cloud.request)
        #expect(localRequest.revisionTarget == cloudRequest.revisionTarget)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(localRequest.input.utf8)) ==
                    JSONDecoder().decode(JSONValue.self, from: Data(cloudRequest.input.utf8)))
        let proposal = try rig.local.complete(replacement: "Reviewed copy.")
        try await rig.wait { rig.store.compareResults[.qwen]?.state == .complete }
        #expect(rig.store.assistantActivity == .working)
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(!rig.store.isWorking)
        _ = try rig.cloud.complete(replacement: "Late conflicting copy.")
        await Task.yield()
        #expect(rig.store.sharedText == "Reviewed copy.")
        #expect(rig.store.compareResults.isEmpty)
        #expect(rig.store.canUndoWorkingCopyEdit)
    }

    @Test func stopSelectionPlacementAndSourceChangesRevokeCandidates() async throws {
        for change in 0..<4 {
            let rig = RevisionStoreRig(); defer { rig.drain() }
            try await rig.begin()
            let proposal = try rig.local.complete(replacement: "Revised copy.")
            try await rig.wait { !rig.store.isWorking }
            switch change {
            case 0: rig.store.cancelWork()
            case 1: rig.store.clearTextSelection()
            case 2: rig.store.placed(at: CGPoint(x: 10, y: 20))
            default: rig.store.share(text: "New source.", name: "new.txt")
            }
            let before = rig.store.sharedText, revision = rig.store.sourceRevision
            rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
            #expect(rig.store.sharedText == before)
            #expect(rig.store.sourceRevision == revision)
            #expect(!rig.store.canUndoWorkingCopyEdit)
            #expect(rig.store.compareResults.values.allSatisfy { $0.revision == nil })
        }
    }

    @Test func stoppedPendingRevisionCannotReturnAsReady() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        rig.store.cancelWork()
        _ = try rig.local.complete(replacement: "Too late.")
        await Task.yield()
        #expect(rig.store.assistantActivity == .stopped)
        #expect(rig.store.compareResults[.qwen]?.revision == nil)
        #expect(rig.store.sharedText == "Original copy.")
    }

    @Test func clarifyDismissWrongIDAndSourceMutationCannotApply() async throws {
        for mutation in 0..<4 {
            let rig = RevisionStoreRig(); defer { rig.drain() }
            try await rig.begin()
            let proposal = try rig.local.complete(replacement: mutation == 0 ? "" : "Revised copy.",
                decision: mutation == 0 ? .clarify : .propose)
            try await rig.wait { !rig.store.isWorking }
            if mutation == 1 { rig.store.dismissPassageRevision(provider: .qwen) }
            if mutation == 3 { rig.store.sharedText = "Intervening bytes." }
            let before = rig.store.sharedText
            rig.store.applyPassageRevision(provider: .qwen, targetID: mutation == 2 ? UUID().uuidString : proposal.target.id)
            #expect(rig.store.sharedText == before)
            #expect(!rig.store.canUndoWorkingCopyEdit)
        }
    }

    @Test func rawTextCannotMasqueradeAsRevisionAndModeChangesAffectOnlyNextSend() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        rig.store.requestsRevision = false
        rig.local.handler?(.text("An unstructured replacement."))
        rig.local.resolve()
        await Task.yield()
        #expect(rig.store.compareResults[.qwen]?.state == .failed)
        #expect(rig.store.sharedText == "Original copy.")
        #expect(rig.local.request?.revisionTarget != nil)
    }

    @Test func newerSharedCopyInvalidatesUndoEvenWithIdenticalBytes() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        rig.store.share(text: rig.store.sharedText, name: "another.txt")
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText == "Revised copy.")
        #expect(!rig.store.canUndoWorkingCopyEdit)
    }

    @Test func exportVerifiesBytesPreservesOriginalRejectsStaleAndFailedWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.txt")
        let bytes = Data("Original 👩🏽‍💻 e\u{301}\r\n".utf8)
        try bytes.write(to: original)
        let rig = RevisionStoreRig(); defer { rig.drain() }
        #expect(rig.store.importWorkingCopy(from: original))
        let revision = rig.store.sourceRevision
        #expect(!rig.store.exportWorkingCopy(to: original, expectedRevision: revision))
        let alias = directory.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        #expect(!rig.store.exportWorkingCopy(to: alias, expectedRevision: revision))
        let hardLink = directory.appendingPathComponent("hard-link.txt")
        try FileManager.default.linkItem(at: original, to: hardLink)
        #expect(!rig.store.exportWorkingCopy(to: hardLink, expectedRevision: revision))
        let caseAlias = directory.appendingPathComponent("ORIGINAL.TXT")
        if FileManager.default.fileExists(atPath: caseAlias.path) {
            #expect(!rig.store.exportWorkingCopy(to: caseAlias, expectedRevision: revision))
        }
        let draft = directory.appendingPathComponent("draft.txt")
        #expect(!rig.store.exportWorkingCopy(to: draft, expectedRevision: revision - 1))
        #expect(!FileManager.default.fileExists(atPath: draft.path))
        #expect(rig.store.exportWorkingCopy(to: draft, expectedRevision: revision))
        #expect(try Data(contentsOf: draft) == bytes)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(!rig.store.exportWorkingCopy(to: original.appendingPathComponent("cannot-write.txt"), expectedRevision: revision))
        #expect(Data(rig.store.sharedText.utf8) == bytes)
        #expect(rig.store.sourceRevision == revision)
    }
}

@MainActor
private final class RevisionStoreRig {
    let local = RevisionStoreClient(), cloud = RevisionStoreClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    lazy var store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: local,
        assistantFactory: { [cloud] _, _ in cloud }, tokenSteward: TokenStewardStore())

    func begin(text: String = "Original copy.", range: NSRange? = nil, compare: Bool = false) async throws {
        store.share(text: text, name: "fixture.txt")
        store.selectText(range: range ?? NSRange(location: 0, length: text.utf16.count), sourceRevision: store.sourceRevision)
        store.preparePassageRevision()
        if compare { store.setAssistantRoute(.compare) }
        store.connectAssistant()
        try await wait { store.connectionState == .ready }
        store.submit()
        try await wait { self.local.request != nil && (!compare || self.cloud.request != nil) }
    }
    func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AssistantFailure.timedOut
    }
    func drain() {
        store.disconnectAssistant(provider: .qwen); store.disconnectAssistant(provider: .codex)
        local.resolve(); cloud.resolve()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RevisionStoreClient: AssistantClient {
    var request: AssistantRequest?
    var handler: (@MainActor (AssistantEvent) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(replacement: String, decision: RevisionDecision = .propose, memoryIDs: [String] = []) throws -> PassageRevisionProposal {
        let target = try #require(request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: decision, replacement: replacement,
            explanation: "Review the proposed wording.", sourceIDs: ["selected-passage"], memoryIDs: memoryIDs)
        handler?(.revision(proposal)); resolve()
        return proposal
    }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
