import SwiftUI

/// A navigation surface over the existing profile's memory owners. The preview
/// is static, contains only real records and never dispatches or persists work.
@MainActor
struct HomeMemoryMapCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var library: ReadingSourceLibrary
    let onExplore: () -> Void
    let onShowcase: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = CompanionGraphSnapshot.empty
    @State private var field = KnowledgeParticleField(snapshot: .empty)
    @State private var libraryNeedsAttention = false
    @State private var checkedAt = Date()

    init(store: CompanionStore, onExplore: @escaping () -> Void, onShowcase: @escaping () -> Void) {
        self.store = store
        library = store.readingSources
        self.onExplore = onExplore
        self.onShowcase = onShowcase
    }

    private var pageCount: Int { library.latestKnowledgePages.count }
    private var lessonCount: Int { store.keptLessons.filter { $0.isValid && ($0.expiresAt.map { $0 > checkedAt } ?? true) }.count }
    private var methodCount: Int { store.documentProcedures.latestProcedures.count }
    private var hasRecords: Bool { !library.sources.isEmpty || pageCount > 0 || methodCount > 0 || store.keptLessons.contains(where: \.isValid) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 28) {
                summary.frame(minWidth: 290)
                preview.frame(width: 270, height: 246)
            }
            VStack(alignment: .leading, spacing: 16) {
                summary
                preview.frame(height: 190)
            }
        }
        .padding(20)
        .background {
            LinearGradient(colors: [WorkspaceTheme.accent.opacity(0.045), .clear],
                startPoint: .topTrailing, endPoint: .bottomLeading)
        }
        .modifier(WorkspaceSurface(emphasis: true))
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceTheme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.memory-map")
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refresh() }
        .onChange(of: library.sources) { _, _ in refresh() }
        .onChange(of: library.knowledgePages) { _, _ in refresh() }
        .onChange(of: library.knowledgeLinks) { _, _ in refresh() }
        .onChange(of: library.loadError) { _, _ in refresh() }
        .onChange(of: store.keptLessons) { _, _ in refresh() }
        .onChange(of: store.documentProcedures.procedures) { _, _ in refresh() }
        .onChange(of: store.documentWork.records) { _, _ in refresh() }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in refresh() }
        .onChange(of: ObjectIdentifier(store.readingSources)) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkspaceEyebrow(text: "Connected memory")
            Text("Your memory, connected.")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(hasRecords
                 ? "Follow sources, ideas, lessons and methods back to the records behind them."
                 : "Keep a source or a useful lesson. Its place in your memory map starts here.")
                .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                recordCount(library.sources.count, title: "sources", identifier: "sources")
                recordCount(pageCount, title: "pages", identifier: "pages")
                recordCount(lessonCount, title: "active lessons", identifier: "lessons")
                recordCount(methodCount, title: "methods", identifier: "methods")
            }
            .padding(.vertical, 2)
            if libraryNeedsAttention {
                Label("Source library needs review", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                    .accessibilityIdentifier("home.memory-map.needs-review")
            }
            HStack(spacing: 10) {
                Button(action: onExplore) {
                    Label("Explore memory", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .accessibilityIdentifier("home.memory-map.explore")
                Button("Present map", systemImage: "arrow.up.left.and.arrow.down.right", action: onShowcase)
                    .buttonStyle(WorkspaceActionStyle())
                    .disabled(!hasRecords)
                    .accessibilityIdentifier("home.memory-map.showcase")
            }
            Button(hasRecords ? "Manage memories" : "Add a source") { store.open(.memory) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .foregroundStyle(WorkspaceTheme.accent)
                .accessibilityIdentifier("home.memory")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        Button(action: onExplore) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(WorkspaceTheme.background.opacity(0.5))
                if hasRecords {
                    KnowledgeParticleView(field: field, nodes: snapshot.nodes, selectedID: nil,
                        spread: 1, pulses: false, reduceMotion: true,
                        tint: store.preferences.seedColor.accent, showsLabels: false, onSelect: { _ in })
                        .allowsHitTesting(false).accessibilityHidden(true)
                        .padding(8)
                    VStack {
                        Spacer()
                        Text(snapshot.truncatedCount > 0 ? "Partial preview · open to inspect" : "Open the map to follow a connection")
                            .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.muted)
                            .padding(.bottom, 9)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(WorkspaceTheme.accent.opacity(0.7))
                        Text("Ready for your first record")
                            .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspaceTheme.line.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open memory map")
        .accessibilityHint("Explore retained sources, pages, lessons and methods.")
        .accessibilityIdentifier("home.memory-map.preview")
    }

    private func recordCount(_ count: Int, title: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count, format: .number)
                .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(title)")
        .accessibilityIdentifier(identifier == "lessons" ? "home.lesson-count" : "home.memory-map.count.\(identifier)")
        .help(identifier == "sources" ? "Source copies retained in this profile. Referenced copies that were removed are not counted."
              : identifier == "pages" ? "The latest record for each authored page, including drafts and withdrawn pages. Open a page to inspect its status."
              : identifier == "methods" ? "Saved method families, including unavailable and withdrawn methods. Open the map to inspect each version."
              : "Explicitly kept lessons, excluding expired ones. Open a lesson to inspect its status.")
    }

    private func refresh() {
        checkedAt = Date()
        let next = store.memoryMapSnapshot()
        if next != snapshot {
            snapshot = next
            field = KnowledgeParticleField(snapshot: next)
        }
        libraryNeedsAttention = !library.isCurrentOnDisk
    }
}
