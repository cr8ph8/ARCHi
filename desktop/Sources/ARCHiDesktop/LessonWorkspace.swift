import SwiftUI

@MainActor
struct KeptLessonsCard: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        WorkspaceCard {
            HStack {
                Label("Lessons you’ve kept", systemImage: "bookmark.circle")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
                Text("\(store.keptLessons.count) / 16").font(.caption).foregroundStyle(.secondary)
            }
            Text("Teach a useful preference in your own words. Kept lessons survive restart and are used only by Qwen on this Mac, for your chosen task or a matching topic phrase. Current instructions take precedence.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).padding(.vertical, 8)
            HStack {
                Button("Keep a lesson…", systemImage: "plus") { store.beginLessonCorrection() }
                    .buttonStyle(.borderedProminent).disabled(store.keptLessons.count >= 16)
                Button("Export kept lessons…") { store.exportLessons() }
                    .disabled(store.keptLessons.isEmpty)
            }
            if store.keptLessons.isEmpty {
                Text("No lessons saved. A good answer does not automatically become a memory.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
            }
            ForEach(store.keptLessons) { lesson in
                Divider().padding(.vertical, 8)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.text).font(.system(size: 13)).textSelection(.enabled)
                        if let scope = lesson.taskScope {
                            Text("Use for · \(scope.title). The topic is a label; it need not appear in your question.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text("Use when the topic phrase appears in your question.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if !lesson.reason.isEmpty {
                            Text("Why you kept it · \(lesson.reason)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text("Revision \(lesson.revision) · kept \(lesson.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let expiry = lesson.expiresAt {
                            Text("Expires \(expiry.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        } else { Text("No expiry set").font(.caption).foregroundStyle(.secondary) }
                        if let source = lesson.source {
                            Text("Bound to \(source.name) · SHA-256 \(source.digest)")
                                .font(.caption2).textSelection(.enabled)
                        }
                        if let origin = lesson.origin {
                            Text("Taught after request \(origin.requestID)")
                                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        HStack {
                            Button("Revise…") { store.beginLessonCorrection(revisingID: lesson.id) }
                                .accessibilityLabel("Revise lesson for \(lesson.topic)")
                            Button("Withdraw", role: .destructive) {
                                store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision)
                            }.accessibilityLabel("Withdraw lesson for \(lesson.topic)")
                        }.padding(.top, 4)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lesson.topic).font(.system(size: 13, weight: .medium))
                        Text(lesson.taskScope.map { "Use for · \($0.title)" } ?? "Use for · Matching topic phrase")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(store.lessonAvailability(lesson)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Text(store.lessonMessage).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                .accessibilityIdentifier("lesson-save-status")
            if !store.keptLessons.isEmpty {
                Text("Revising or withdrawing clears temporary local context and stops an active local reply. Codex keeps its own work. Exported copies are yours to remove separately.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .disabled(store.isShuttingDown)
        .sheet(item: $store.lessonDraft) { draft in
            LessonCorrectionEditor(store: store, draft: draft)
        }
    }
}

@MainActor
struct LessonCorrectionEditor: View {
    @ObservedObject var store: CompanionStore
    @State var draft: LessonCorrectionDraft
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case topic, lesson, reason }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.prior == nil ? "Teach ARCHi a lesson" : "Revise this lesson")
                .font(.system(size: 22, weight: .medium, design: .rounded))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keep a useful preference or correction. This saves your words on this Mac for local Qwen requests within the scope you choose.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Picker("Use for", selection: $draft.taskScope) {
                        Text("Matching topic phrase").tag(HamptonTaskScope?.none)
                        ForEach(HamptonTaskScope.allCases) { scope in
                            Text(scope.title).tag(Optional(scope))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("lesson-task-scope")
                    if let scope = draft.taskScope {
                        Text("Used for \(scope.title.lowercased()). The topic becomes a label; it does not need to appear in the question. Exact-copy restrictions and expiry still apply.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.taskScope == nil ? "Topic phrase" : "Topic label").font(.system(size: 12, weight: .medium))
                        TextField(draft.taskScope == nil ? "For example: drawing" : "For example: clear, concise writing", text: $draft.topic)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(draft.taskScope == nil ? "Topic phrase" : "Topic label")
                            .accessibilityIdentifier("lesson-topic")
                            .focused($focusedField, equals: .topic)
                        if draft.taskScope == nil {
                            Text("Used when these whole words appear in your question, ignoring case and accents. A topic in the shared document alone will not activate it.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if let prior = draft.prior {
                        Text("Previously · \(prior.text)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What should ARCHi remember?").font(.system(size: 12, weight: .medium))
                        TextEditor(text: $draft.text).frame(height: 90)
                            .focused($focusedField, equals: .lesson)
                            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { event in
                                focusedField = event.modifiers.contains(.shift) || event.key == KeyEquivalent("\u{19}") ? .topic : .reason
                                return .handled
                            }
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                            .accessibilityLabel("Lesson text").accessibilityIdentifier("lesson-text")
                        Text("\(draft.text.count) / 600 characters").font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Why this helps you (optional)", text: $draft.reason)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Reason for lesson")
                        .focused($focusedField, equals: .reason)
                    Toggle("Use only with this exact shared copy", isOn: Binding(
                        get: { draft.source != nil },
                        set: { draft.source = $0 ? store.currentLessonSource : nil }))
                        .disabled(store.currentLessonSource == nil && draft.source == nil)
                    if let source = draft.source {
                        Text(source.name + " · changed content makes this lesson unavailable")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Toggle("Set an expiry", isOn: Binding(get: { draft.expiresAt != nil },
                        set: { draft.expiresAt = $0 ? Date().addingTimeInterval(30 * 24 * 3600) : nil }))
                    if draft.expiresAt != nil {
                        DatePicker("Expires", selection: Binding(get: { draft.expiresAt ?? Date() },
                            set: { draft.expiresAt = $0 }), in: Date()..., displayedComponents: [.date])
                    }
                    Text(store.lessonMessage).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("lesson-editor-status")
                }.padding(2)
            }.frame(maxHeight: 430)
            Divider()
            HStack {
                Button("Do not save") { store.discardLessonDraft() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.prior == nil ? "Keep lesson" : "Keep revision") { store.keepLesson(draft) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.topic.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                        || draft.topic.count > 80 || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.text.count > 600 || draft.reason.count > 300)
                    .accessibilityIdentifier("lesson-keep")
            }
        }.padding(24).frame(width: 520).onAppear { focusedField = .topic }
    }
}

@MainActor
struct LessonReplyControls: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider
    var body: some View {
        if let result = store.compareResults[provider], result.state == .complete, !result.text.isEmpty {
            Button("Teach a correction…", systemImage: "square.and.pencil") {
                store.beginLessonCorrection(for: provider)
            }.buttonStyle(.borderless).font(.system(size: 11))
                .help("Write and review a lesson. No answer is saved automatically; kept lessons are used only by local Qwen.")
        }
    }
}
