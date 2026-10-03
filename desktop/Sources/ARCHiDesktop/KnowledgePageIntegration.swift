import Foundation

@MainActor
extension CompanionStore {
    var currentKnowledgeContext: KnowledgePageContext? {
        guard !selectedKnowledgePages.isEmpty, knowledgeDependenciesAreCurrent(selectedKnowledgePages) else { return nil }
        let pages = selectedKnowledgePages.compactMap { binding in
            readingSources.latestKnowledgePages.first { $0.binding == binding }
        }
        let quotes = pages.map { $0.anchors.compactMap { readingSources.quote(for: $0) } }
        return KnowledgePageContext.make(pages: pages, quotes: quotes)
    }

    var selectedKnowledgePageIssue: String? {
        guard !selectedKnowledgePages.isEmpty else { return nil }
        guard knowledgeDependenciesAreCurrent(selectedKnowledgePages) else {
            return "A selected page or its supporting source changed. Review and select the current version, or detach the pages."
        }
        return currentKnowledgeContext == nil ? "Selected pages and passages exceed the local context limit. Use fewer or shorter passages." : nil
    }

    func knowledgeDependenciesAreCurrent(_ bindings: [KnowledgePageBinding]?) -> Bool {
        guard let bindings else { return true }
        guard KnowledgePageBinding.valid(bindings), readingSources.isCurrentOnDisk else { return false }
        return bindings.allSatisfy { binding in
            guard let page = readingSources.latestKnowledgePages.first(where: { $0.binding == binding }) else { return false }
            return readingSources.availability(of: page) == nil
        }
    }

    func lessonDependenciesAreCurrent(_ origin: LessonOrigin?) -> Bool {
        readingDependenciesAreCurrent(origin?.readingSources) && knowledgeDependenciesAreCurrent(origin?.knowledgePages)
    }

    /// Prepares exact local context without sending. The map can retain its view
    /// and composer while other callers continue opening the assistant.
    @discardableResult
    func useKnowledgePageInChat(_ page: KnowledgePage, openAssistant: Bool = true) -> Bool {
        guard !isShuttingDown else { return false }
        guard !hasOpenKnowledgeDraft else {
            knowledgePageMessage = "Save or discard the open page or connection draft first."
            return false
        }
        // Availability checks the current disk library, exact latest page
        // version, review state and source passages. Never substitute a revision.
        if let issue = readingSources.availability(of: page) {
            knowledgePageMessage = issue
            return false
        }
        var next = selectedKnowledgePages.filter { $0.id != page.id }
        guard next.count < 4 else { knowledgePageMessage = "Use up to four pages at once."; return false }
        next.append(page.binding)
        invalidateReadingContext(reason: "Selected knowledge pages for local chat. Nothing sent yet.")
        requestsRevision = false
        selectedKnowledgePages = next
        setAssistantRoute(.automatic)
        knowledgePageMessage = "Selected for local chat. Your shared document stays unchanged and is not sent with these pages."
        if openAssistant { open(.assistant) }
        return true
    }

    func detachKnowledgePages() {
        guard !isShuttingDown else { return }
        invalidateReadingContext(reason: "Knowledge pages detached. Earlier page context was cleared.")
        selectedKnowledgePages = []
    }

    private var canChangeKnowledgePages: Bool {
        guard !isShuttingDown, !isWorking else {
            knowledgePageMessage = "Finish the current request before changing a knowledge page."
            return false
        }
        guard readingSources.loadError == nil, readingSources.isCurrentOnDisk else {
            knowledgePageMessage = readingSources.loadError ?? "The source library changed outside this window. Reopen before editing."
            return false
        }
        return true
    }

    func beginKnowledgePage(_ page: KnowledgePage? = nil) {
        guard canChangeKnowledgePages else { return }
        guard !hasOpenKnowledgeDraft else {
            knowledgePageMessage = "Save or discard the open page draft first."
            open(.memory)
            return
        }
        if let page, !readingSources.latestKnowledgePages.contains(page) {
            knowledgePageMessage = "This page has a newer version. Open that version before revising."
            return
        }
        knowledgePageMessage = nil
        knowledgePageDraft = KnowledgePageDraft(prior: page)
        open(.memory)
    }

    @discardableResult
    func saveKnowledgePage(prior: KnowledgePage?, title: String, body: String,
                           kind: KnowledgePageKind, anchors: [KnowledgeAnchor]) -> Bool {
        guard canChangeKnowledgePages else { return false }
        do {
            let page = try readingSources.saveKnowledgePage(id: prior?.id, expectedRevision: prior?.revision,
                title: title, body: body, kind: kind, anchors: anchors)
            selectedKnowledgePageID = page.id
            knowledgePageDraft = nil
            invalidateReadingContext(reason: "Knowledge page saved. Earlier answer context was cleared.")
            knowledgePageMessage = "Draft saved on this Mac. Review its passages when ready."
            return true
        } catch {
            knowledgePageMessage = error.localizedDescription
            return false
        }
    }

    func reviewKnowledgePage(_ page: KnowledgePage) {
        guard canChangeKnowledgePages else { return }
        do {
            let reviewed = try readingSources.reviewKnowledgePage(id: page.id, expectedRevision: page.revision)
            selectedKnowledgePageID = reviewed.id
            invalidateReadingContext(reason: "Knowledge page reviewed. Earlier answer context was cleared.")
            knowledgePageMessage = "Your review is recorded. It does not certify the claim as true or teach a lesson automatically."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    func withdrawKnowledgePage(_ page: KnowledgePage) {
        guard canChangeKnowledgePages else { return }
        do {
            _ = try readingSources.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
            invalidateReadingContext(reason: "Knowledge page withdrawn. Earlier answer context was cleared.")
            knowledgePageMessage = "Page withdrawn. Earlier versions remain in its history."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    @discardableResult
    func saveKnowledgeLink(prior: KnowledgePageLink?, from: KnowledgePageBinding,
                           to: KnowledgePageBinding, kind: KnowledgePageLinkKind, rationale: String) -> Bool {
        guard canChangeKnowledgePages, knowledgePageDraft == nil else { return false }
        do {
            _ = try readingSources.saveKnowledgeLink(id: prior?.id, expectedRevision: prior?.revision,
                from: from, to: to, kind: kind, rationale: rationale)
            knowledgePageMessage = "Connection saved as a draft. Review both pages and their passages before marking it reviewed."
            return true
        } catch { knowledgePageMessage = error.localizedDescription; return false }
    }

    func reviewKnowledgeLink(_ link: KnowledgePageLink) {
        guard canChangeKnowledgePages, !hasOpenKnowledgeDraft else { return }
        do {
            _ = try readingSources.reviewKnowledgeLink(id: link.id, expectedRevision: link.revision)
            knowledgePageMessage = "Your connection review is recorded. It can suggest related pages; it does not certify either claim."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    func withdrawKnowledgeLink(_ link: KnowledgePageLink) {
        guard canChangeKnowledgePages, !hasOpenKnowledgeDraft else { return }
        do {
            _ = try readingSources.withdrawKnowledgeLink(id: link.id, expectedRevision: link.revision)
            knowledgePageMessage = "Connection withdrawn from suggestions. Its earlier versions remain in history."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    func beginRelationshipPage(_ kind: RelationshipMemoryKind, person: KnowledgePage? = nil) {
        guard canChangeKnowledgePages, !hasOpenKnowledgeDraft else { return }
        if kind != .person {
            guard let person, person.relationship?.kind == .person,
                  readingSources.availability(of: person) == nil else {
                knowledgePageMessage = "Review the current person record before adding an encounter or commitment."
                return
            }
        }
        knowledgePageMessage = nil
        knowledgePageDraft = KnowledgePageDraft(relationshipKind: kind, person: person?.binding)
        open(.memory)
    }

    @discardableResult
    func saveRelationshipPage(prior: KnowledgePage?, title: String, body: String,
                              metadata: RelationshipMemoryMetadata, anchors: [KnowledgeAnchor]) -> Bool {
        guard canChangeKnowledgePages else { return false }
        do {
            let page = try readingSources.saveRelationshipPage(id: prior?.id, expectedRevision: prior?.revision,
                title: title, body: body, metadata: metadata, anchors: anchors)
            selectedKnowledgePageID = page.id
            knowledgePageDraft = nil
            invalidateReadingContext(reason: "Relationship record saved. Earlier context was cleared.")
            knowledgePageMessage = "Draft saved on this Mac. Review the record and its linked note before using it."
            return true
        } catch { knowledgePageMessage = error.localizedDescription; return false }
    }

    func markRelationshipCommitment(_ page: KnowledgePage, status: RelationshipCommitmentStatus) {
        guard canChangeKnowledgePages else { return }
        do {
            let revised = try readingSources.markRelationshipCommitment(id: page.id,
                expectedRevision: page.revision, status: status)
            selectedKnowledgePageID = revised.id
            invalidateReadingContext(reason: "Commitment status changed. Earlier context was cleared.")
            knowledgePageMessage = "Your status report is saved as a draft. Review it before using it in preparation."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    /// Replaces previous selections so a brief never silently includes another person's pages.
    /// It prepares local context only; the user still writes and sends the request.
    func prepareRelationshipConversation(person: KnowledgePage, records: [KnowledgePage]) {
        guard canChangeKnowledgePages, !hasOpenKnowledgeDraft else { return }
        let pages = [person] + records
        guard person.relationship?.kind == .person, pages.count <= 4,
              Set(pages.map(\.id)).count == pages.count,
              records.allSatisfy({ $0.relationship?.person == person.binding }),
              pages.allSatisfy({ readingSources.availability(of: $0) == nil }),
              KnowledgePageContext.make(pages: pages,
                quotes: pages.map { $0.anchors.compactMap { readingSources.quote(for: $0) } }) != nil else {
            knowledgePageMessage = "Choose a current reviewed person and up to three short, reviewed related records. Check their passages if preparation is unavailable."
            return
        }
        invalidateReadingContext(reason: "Selected relationship records for local preparation. Nothing sent yet.")
        requestsRevision = false
        selectedKnowledgePages = pages.map(\.binding)
        setAssistantRoute(.automatic)
        knowledgePageMessage = "Selected \(pages.count) records for local chat. Write your preparation question when ready."
        open(.assistant)
    }

    @discardableResult
    func keepRelationshipSource(title: String, text: String) -> Bool {
        guard canChangeKnowledgePages else { return false }
        do {
            _ = try readingSources.keep(title: title, text: text)
            invalidateReadingContext(reason: "A relationship note was kept on this Mac.")
            knowledgePageMessage = "Note kept. Add a person, encounter or commitment and link its exact passage."
            return true
        } catch { knowledgePageMessage = error.localizedDescription; return false }
    }
}
