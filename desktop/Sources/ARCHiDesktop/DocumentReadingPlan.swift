import Foundation

struct DocumentReadingSection: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let location: Int
    let length: Int
    let text: String
    let sha256: String
}

/// Deterministic retrieval from one supplied copy. These spans identify source
/// bytes; selecting or citing them does not verify the meaning of an answer.
struct DocumentReadingPlan: Equatable, Sendable {
    let sourceDigest: String
    let questionDigest: String
    let sections: [DocumentReadingSection]
    let totalSections: Int
    /// Retained section text only. The input limit additionally includes titles.
    let totalUTF8Bytes: Int
    let isPartial: Bool

    static let maximumSections = 6
    static let maximumRetainedBytes = 9_000
    private static let maximumChunkBytes = 2_600
    private static let maximumTitleBytes = 240
    private static let maximumSourceBytes = 100_000
    private static let maximumQuestionBytes = 16_000

    var sourceIDs: [String] { sections.map(\.id) }

    var digest: String {
        struct Binding: Encodable {
            let sourceDigest: String
            let questionDigest: String
            let sections: [DocumentReadingSection]
            let totalSections: Int
            let totalUTF8Bytes: Int
            let isPartial: Bool
        }
        let value = Binding(sourceDigest: sourceDigest, questionDigest: questionDigest,
            sections: sections, totalSections: totalSections, totalUTF8Bytes: totalUTF8Bytes, isPartial: isPartial)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(value) else { return "" }
        return LessonSource.digest(of: String(decoding: bytes, as: UTF8.self))
    }

    /// Validates exact source/question bytes, span identities and coverage.
    /// It intentionally does not rerun the ranking policy or infer entailment.
    func matches(text: String, question: String, selection: DocumentSelection?) -> Bool {
        guard !text.isEmpty, text.utf8.count <= Self.maximumSourceBytes,
              question.utf8.count <= Self.maximumQuestionBytes,
              sourceDigest == LessonSource.digest(of: text), questionDigest == LessonSource.digest(of: question),
              (1...Self.maximumSections).contains(sections.count), totalSections >= sections.count,
              totalSections <= text.utf16.count, Set(sourceIDs).count == sections.count,
              totalUTF8Bytes == sections.reduce(0, { $0 + $1.text.utf8.count }),
              sections.reduce(0, { $0 + $1.text.utf8.count + $1.title.utf8.count }) <= Self.maximumRetainedBytes else { return false }
        let boundaries = Self.boundaries(in: text)
        let source = text as NSString
        var end = 0
        for section in sections.sorted(by: { $0.location < $1.location }) {
            guard section.location >= end, section.location <= source.length, section.length > 0,
                  section.length <= source.length - section.location,
                  boundaries.contains(section.location), boundaries.contains(section.location + section.length),
                  !section.title.isEmpty, section.title.utf8.count <= Self.maximumTitleBytes,
                  section.id == Self.sectionID(sourceDigest, location: section.location, length: section.length),
                  section.sha256 == LessonSource.digest(of: section.text),
                  source.substring(with: NSRange(location: section.location, length: section.length)).utf8.elementsEqual(section.text.utf8)
            else { return false }
            end = section.location + section.length
        }
        guard isPartial == !Self.coversWholeSource(sections, length: source.length) else { return false }
        guard let selection else { return true }
        guard Self.validSelection(selection, text: text, boundaries: boundaries) else { return false }
        return sections.contains { Self.contains($0, range: selection.range) }
    }

    static func make(text: String, question: String, selection: DocumentSelection?, lane: HamptonQ2ELane,
                     preferredSectionIDs: [String] = []) -> DocumentReadingPlan? {
        guard !text.isEmpty, text.utf8.count <= maximumSourceBytes,
              question.utf8.count <= maximumQuestionBytes else { return nil }
        let boundaries = Self.boundaries(in: text)
        if let selection, !validSelection(selection, text: text, boundaries: boundaries) { return nil }
        let sourceDigest = LessonSource.digest(of: text)
        let indexed = index(text, sourceDigest: sourceDigest)
        guard !indexed.isEmpty else { return nil }
        let queryTerms = Self.terms(in: question)
        let preferred = Set(preferredSectionIDs.prefix(64))
        let scored = indexed.enumerated().map { index, section in
            Candidate(index: index, section: section,
                relevance: queryTerms.intersection(Self.terms(in: section.title)).count * 8
                    + queryTerms.intersection(Self.terms(in: section.text)).count * 2,
                preferred: preferred.contains(section.id))
        }
        var retained: [DocumentReadingSection] = []
        var retainedBytes = 0
        var anchor: Int?
        func append(_ section: DocumentReadingSection) -> Bool {
            let count = section.text.utf8.count + section.title.utf8.count
            guard retained.count < maximumSections, count <= maximumRetainedBytes - retainedBytes,
                  !retained.contains(where: { overlaps($0, section) }) else { return false }
            retained.append(section); retainedBytes += count
            return true
        }
        if let selection {
            anchor = indexed.firstIndex { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), selection.range).length > 0 }
            // Prefer the complete indexed section when it fits. A larger or
            // boundary-crossing selection receives its own exact source span.
            if let containing = indexed.first(where: { contains($0, range: selection.range) }), append(containing) {
                // Selection coverage is established by this complete section.
            } else {
                let selected = section(text: selection.quote, title: "Selected passage", location: selection.range.location,
                    sourceDigest: sourceDigest)
                guard append(selected) else { return nil }
            }
        }
        let baseOrder = scored.sorted { left, right in
            let l = left.relevance + (lane == .retain && left.preferred ? 24 : 0)
            let r = right.relevance + (lane == .retain && right.preferred ? 24 : 0)
            return l == r ? left.index < right.index : l > r
        }
        if retained.isEmpty {
            for candidate in baseOrder {
                if append(candidate.section) { anchor = candidate.index; break }
            }
        }
        guard !retained.isEmpty else { return nil }
        if lane == .repair, let anchor {
            // Neighboring source spans add context without synthesizing text.
            for distance in 1...2 {
                for neighbor in [anchor - distance, anchor + distance] where indexed.indices.contains(neighbor) {
                    _ = append(indexed[neighbor])
                }
            }
        }
        // Re-rank against already retained branches for bounded diversity.
        // Relevance dominates the small diversity tie-break; no semantic score.
        var considered = Set<String>()
        while retained.count < maximumSections {
            let branches = Set(retained.map { branch($0.title) })
            let available = scored.filter { candidate in
                !considered.contains(candidate.section.id)
                    && !retained.contains(where: { overlaps($0, candidate.section) })
                    && candidate.section.text.utf8.count + candidate.section.title.utf8.count <= maximumRetainedBytes - retainedBytes
            }
            guard let best = available.max(by: { left, right in
                func weight(_ candidate: Candidate) -> Int {
                    candidate.relevance * 16 + (lane == .retain && candidate.preferred ? 384 : 0)
                        + (lane == .expand && !branches.contains(branch(candidate.section.title)) ? 4 : 0)
                }
                let l = weight(left), r = weight(right)
                return l == r ? left.index > right.index : l < r
            }) else { break }
            considered.insert(best.section.id)
            _ = append(best.section)
        }
        retained.sort { $0.location < $1.location }
        let plan = DocumentReadingPlan(sourceDigest: sourceDigest, questionDigest: LessonSource.digest(of: question),
            sections: retained, totalSections: indexed.count,
            totalUTF8Bytes: retained.reduce(0, { $0 + $1.text.utf8.count }),
            isPartial: !coversWholeSource(retained, length: text.utf16.count))
        return plan.matches(text: text, question: question, selection: selection) ? plan : nil
    }

    private struct Candidate {
        let index: Int
        let section: DocumentReadingSection
        let relevance: Int
        let preferred: Bool
    }

    private struct Fence {
        let marker: Character
        let count: Int
    }

    private static func index(_ text: String, sourceDigest: String) -> [DocumentReadingSection] {
        var sections: [DocumentReadingSection] = []
        var parents: [(level: Int, title: String)] = []
        var title = "Document", start = text.startIndex
        var fence: Fence?
        func flush(until end: String.Index) {
            guard start < end else { return }
            var chunk = "", bytes = 0
            var location = start.utf16Offset(in: text)
            for character in text[start..<end] {
                let next = String(character), count = next.utf8.count
                while bytes > 0 && bytes + count > maximumChunkBytes {
                    // Prefer a recent complete line, then a word boundary.
                    // Scanning only this bounded buffer and emitting at least
                    // its final-quarter threshold keeps ordinary text linear.
                    var scannedBytes = 0
                    var newline: String.Index?, whitespace: String.Index?
                    for index in chunk.indices {
                        let value = chunk[index]
                        scannedBytes += String(value).utf8.count
                        guard scannedBytes >= maximumChunkBytes * 3 / 4 else { continue }
                        let after = chunk.index(after: index)
                        if value.isNewline { newline = after }
                        if value.isWhitespace { whitespace = after }
                    }
                    let boundary = newline ?? whitespace ?? chunk.endIndex
                    let emitted = String(chunk[..<boundary])
                    let remainder = String(chunk[boundary...])
                    sections.append(section(text: emitted, title: title, location: location, sourceDigest: sourceDigest))
                    location += emitted.utf16.count
                    bytes -= emitted.utf8.count
                    chunk = remainder
                }
                // An oversized grapheme remains one indexed span. Retrieval
                // can omit it; it may never split its scalar sequence to fit.
                chunk += next; bytes += count
            }
            if !chunk.isEmpty { sections.append(section(text: chunk, title: title, location: location, sourceDigest: sourceDigest)) }
        }
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = String(text[range])
            if let active = fence {
                if isClosingFence(line, fence: active) { fence = nil }
                return
            }
            if let opening = openingFence(line) { fence = opening; return }
            guard let heading = heading(line) else { return }
            flush(until: range.lowerBound)
            parents.removeAll { $0.level >= heading.level }
            parents.append(heading)
            title = boundedTitle(parents.map(\.title).joined(separator: " › "))
            start = range.lowerBound
        }
        flush(until: text.endIndex)
        return sections
    }

    private static func unindented(_ line: String) -> Substring? {
        var value = line[...], spaces = 0
        while value.first == " " { spaces += 1; value.removeFirst(); if spaces > 3 { return nil } }
        return value
    }

    private static func heading(_ line: String) -> (level: Int, title: String)? {
        guard var value = unindented(line) else { return nil }
        var level = 0
        while value.first == "#" { value.removeFirst(); level += 1; if level > 6 { return nil } }
        guard level > 0, value.isEmpty || value.first == " " || value.first == "\t" else { return nil }
        var title = value.trimmingCharacters(in: .whitespaces)
        if title.last == "#" {
            var closing = title.endIndex
            while closing > title.startIndex && title[title.index(before: closing)] == "#" { closing = title.index(before: closing) }
            if closing == title.startIndex || title[title.index(before: closing)].isWhitespace {
                title = String(title[..<closing]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (level, boundedTitle(title.isEmpty ? "Untitled section" : title))
    }

    private static func openingFence(_ line: String) -> Fence? {
        guard var value = unindented(line), let marker = value.first, marker == "`" || marker == "~" else { return nil }
        var count = 0
        while value.first == marker { value.removeFirst(); count += 1 }
        guard count >= 3, marker != "`" || !value.contains("`") else { return nil }
        return Fence(marker: marker, count: count)
    }

    private static func isClosingFence(_ line: String, fence: Fence) -> Bool {
        guard var value = unindented(line) else { return false }
        var count = 0
        while value.first == fence.marker { value.removeFirst(); count += 1 }
        return count >= fence.count && value.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func section(text: String, title: String, location: Int, sourceDigest: String) -> DocumentReadingSection {
        DocumentReadingSection(id: sectionID(sourceDigest, location: location, length: text.utf16.count),
            title: title, location: location, length: text.utf16.count, text: text, sha256: LessonSource.digest(of: text))
    }

    private static func sectionID(_ digest: String, location: Int, length: Int) -> String {
        "document-section-" + LessonSource.digest(of: "document-section/v1|\(digest)|\(location)|\(length)")
    }

    private static func boundedTitle(_ text: String) -> String {
        guard text.utf8.count > maximumTitleBytes else { return text }
        var result = "", bytes = 0
        for character in text {
            let value = String(character)
            guard bytes + value.utf8.count <= maximumTitleBytes - 3 else { break }
            result += value; bytes += value.utf8.count
        }
        return result + "…"
    }

    private static func terms(in text: String) -> Set<String> {
        let ignored: Set<String> = ["a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "was", "with"]
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(tokens.filter { !$0.isEmpty && !ignored.contains($0) })
    }

    private static func branch(_ title: String) -> String {
        // Most Markdown copies share one H1. Distinguish its child sections
        // while keeping deeper descendants together for diversity ranking.
        title.components(separatedBy: " › ").prefix(2).joined(separator: " › ")
    }

    private static func boundaries(in text: String) -> Set<Int> {
        var offsets: Set<Int> = [0], offset = 0
        for character in text { offset += String(character).utf16.count; offsets.insert(offset) }
        return offsets
    }

    private static func validSelection(_ selection: DocumentSelection, text: String, boundaries: Set<Int>) -> Bool {
        selection.matches(text: text, sourceRevision: selection.sourceRevision)
            && boundaries.contains(selection.range.location)
            && boundaries.contains(selection.range.location + selection.range.length)
    }

    private static func contains(_ section: DocumentReadingSection, range: NSRange) -> Bool {
        range.location >= section.location && range.length <= section.length
            && range.location - section.location <= section.length - range.length
    }

    private static func overlaps(_ first: DocumentReadingSection, _ second: DocumentReadingSection) -> Bool {
        NSIntersectionRange(NSRange(location: first.location, length: first.length),
                            NSRange(location: second.location, length: second.length)).length > 0
    }

    private static func coversWholeSource(_ sections: [DocumentReadingSection], length: Int) -> Bool {
        var end = 0
        for section in sections.sorted(by: { $0.location < $1.location }) {
            guard section.location == end else { return false }
            end += section.length
        }
        return end == length
    }
}
