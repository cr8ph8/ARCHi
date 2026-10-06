import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ARCHiSpatial

/// A visit-only image canvas. It hands reviewed text to the existing working
/// copy; it cannot save memory, create an identity or execute a model request.
@MainActor
struct ImageRegionImportSheet: View {
    @ObservedObject var store: CompanionStore
    let context: PastedDocumentImportContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: ImageRegionImage?
    @State private var region: ImageRegionRect?
    @State private var title = ""
    @State private var recognized: String?
    @State private var reviewed = ""
    @State private var message: String?
    @State private var busy = false
    @State private var ticket = UUID()
    @State private var task: Task<Void, Never>?
    @State private var pendingDiscard: DiscardAction?
    private enum DiscardAction: String, Identifiable {
        case close, image, region
        var id: String { rawValue }
    }

    private var document: ImageRegionDocument? {
        guard let image, let region,
              let source = ImageRegionSource(imageSHA256: image.imageSHA256,
                  pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, region: region) else { return nil }
        return ImageRegionDocument(source: source, originalRecognition: recognized ?? "", reviewedText: reviewed,
            title: title, method: recognized == nil ? .userDescription : .localOCR)
    }
    private var blocked: String? { store.pastedDocumentImportBlockReason(context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work with an image region").font(.title2.weight(.medium))
                    Text("Choose a region, review its text, then use your existing memories and methods.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose image…") { request(.image) }.disabled(busy)
                    .accessibilityIdentifier("image-region.choose")
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    if let image {
                        ImageRegionMemoryView(store: store, image: image, region: region,
                            onSelect: reviewed.isEmpty && !busy ? { region = $0; recognized = nil; message = nil } : nil)
                            .id(ObjectIdentifier(store.readingSources))
                        HStack {
                            Text(region == nil ? "Drag over the part you want to work with." : "Selected region · original image stays unchanged")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Whole image") {
                                region = ImageRegionRect(x: 0, y: 0, width: 1, height: 1)
                                recognized = nil; message = nil
                            }.disabled(busy || !reviewed.isEmpty)
                            Button("Clear region") { request(.region) }.disabled(busy || region == nil)
                        }
                    } else {
                        ContentUnavailableView("Choose an image", systemImage: "photo",
                            description: Text("PNG, JPEG, HEIC or TIFF. The image is read locally."))
                            .frame(height: 330)
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Region title", text: $title).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("image-region.title")
                    Button("Read text locally", systemImage: "text.viewfinder", action: readRegion)
                        .disabled(image == nil || region == nil || busy || !reviewed.isEmpty || blocked != nil)
                        .accessibilityIdentifier("image-region.read")
                    Text(recognized == nil ? "Describe this region, or read its text locally." : "Review the recognized text and correct any mistakes.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $reviewed).font(.system(size: 13))
                        .frame(minHeight: 160, maxHeight: 240).border(.quaternary)
                        .disabled(region == nil || busy)
                        .accessibilityLabel("Reviewed region text").accessibilityIdentifier("image-region.text")
                    Text("\(reviewed.utf8.count.formatted()) / 60,000 bytes")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Only this reviewed text and its source receipt enter Work together. Image pixels stay local. Nothing is sent until you choose Send.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let document {
                        DisclosureGroup("Source receipt") {
                            Text("Image SHA-256: \(document.source.imageSHA256)")
                                .textSelection(.enabled).font(.system(size: 10, design: .monospaced))
                            Text("\(document.source.pixelWidth) × \(document.source.pixelHeight) · upright image · normalized top-left region")
                                .font(.caption2)
                        }
                    }
                }.frame(width: 290)
            }
            if busy { ProgressView("Reading locally…").controlSize(.small) }
            if let notice = blocked ?? message {
                Text(notice).font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("image-region.notice")
            }
            HStack {
                Button("Cancel") { request(.close) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use in Work together") {
                    guard let document, let image else { return }
                    if store.importImageRegion(document, image: image, context: context) { dismiss() }
                    else { message = store.status }
                }.buttonStyle(.borderedProminent).disabled(document == nil || busy || blocked != nil)
                    .accessibilityIdentifier("image-region.use")
            }
        }.padding(22).frame(width: 950, height: 730)
            .interactiveDismissDisabled(!reviewed.isEmpty || busy)
            .onAppear { store.isImageRegionImportPresented = true }
            .onDisappear { cancel(); store.isImageRegionImportPresented = false }
            .confirmationDialog("Discard this region draft?", isPresented: Binding(
                get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } })) {
                Button("Discard region draft", role: .destructive) {
                    guard let action = pendingDiscard else { return }
                    pendingDiscard = nil; perform(action)
                }
                Button("Keep editing", role: .cancel) { pendingDiscard = nil }
            } message: { Text("This region text has not been added to your working copy.") }
    }

    private func cancel() { ticket = UUID(); task?.cancel(); task = nil; busy = false }
    private func request(_ action: DiscardAction) {
        if !reviewed.isEmpty { pendingDiscard = action } else { perform(action) }
    }
    private func perform(_ action: DiscardAction) {
        if action == .close { cancel(); dismiss(); return }
        if action == .region { cancel(); region = nil; reviewed = ""; recognized = nil; message = nil; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cancel(); let current = ticket; busy = true; message = nil
        task = Task {
            do {
                let loaded = try await ImageRegionReader.load(url: url)
                guard current == ticket, !Task.isCancelled else { return }
                guard blocked == nil else { busy = false; message = blocked; return }
                image = loaded; region = nil; recognized = nil; reviewed = ""
                title = String(loaded.filename.prefix(100)) + " · region"
            } catch {
                guard current == ticket, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
            busy = false; task = nil
        }
    }
    private func readRegion() {
        guard let image, let region, reviewed.isEmpty, blocked == nil else { return }
        cancel(); let current = ticket; busy = true; message = nil
        task = Task {
            do {
                let result = try await ImageRegionReader.recognize(image: image, region: region)
                guard current == ticket, !Task.isCancelled, self.image?.id == image.id, self.region == region else { return }
                guard blocked == nil else { busy = false; message = blocked; return }
                if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    message = "No text was recognized. You can describe the selected region yourself."
                } else { recognized = result; reviewed = result }
            } catch {
                guard current == ticket, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
            busy = false; task = nil
        }
    }
}

@MainActor
struct ImageRegionCanvas: View {
    let image: ImageRegionImage
    let region: ImageRegionRect?
    var onSelect: ((ImageRegionRect) -> Void)?
    @State private var drag: ImageRegionRect?

    static func imageFrame(pixelWidth: Int, pixelHeight: Int, in size: CGSize) -> CGRect {
        guard pixelWidth > 0, pixelHeight > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / Double(pixelWidth), size.height / Double(pixelHeight))
        let w = Double(pixelWidth) * scale, h = Double(pixelHeight) * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    var body: some View {
        GeometryReader { geometry in
            let frame = Self.imageFrame(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, in: geometry.size)
            ZStack {
                Color.black.opacity(0.15)
                Image(decorative: image.cgImage, scale: 1).resizable()
                    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                if let selected = drag ?? region {
                    let rect = selected.displayed(in: frame)
                    Rectangle().stroke(WorkspaceTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .background(WorkspaceTheme.accent.opacity(0.07))
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard onSelect != nil else { return }
                        drag = ImageRegionRect.selection(from: value.startLocation, to: value.location, in: frame)
                    }.onEnded { value in
                        defer { drag = nil }
                        guard let onSelect, let selection = ImageRegionRect.selection(
                            from: value.startLocation, to: value.location, in: frame) else { return }
                        onSelect(selection)
                    })
        }.clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel("\(image.filename). \(region == nil ? "No region selected" : "Image region selected")")
            .accessibilityIdentifier("image-region.canvas")
    }
}

/// Existing graph records gather around an explicit target. Word matches are
/// navigation suggestions, never new relationships or evidence of interest.
@MainActor
struct ImageRegionMemoryView: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var library: ReadingSourceLibrary
    let image: ImageRegionImage
    let region: ImageRegionRect?
    var onSelect: ((ImageRegionRect) -> Void)?
    @State private var query = ""
    @State private var hits: [KnowledgeRetrievalHit] = []
    @State private var selectedID: String?
    @State private var message: String?
    @State private var attractionLease: UUID?
    @State private var attractionScene: String?
    @State private var canvas = CGSize(width: 500, height: 330)
    @State private var showsInspector = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(store: CompanionStore, image: ImageRegionImage, region: ImageRegionRect?,
         onSelect: ((ImageRegionRect) -> Void)? = nil) {
        self.store = store; self.image = image; self.region = region; library = store.readingSources
        self.onSelect = onSelect
    }
    private var paused: Bool { reduceMotion || store.preferences.reduceMotion || store.preferences.quiet || !store.memoryParticleMotionEnabled }
    var body: some View {
        let scene = store.companionParticleScene()
        let valid = hits.filter { hit in
            guard let binding = hit.pageBinding, store.knowledgeDependenciesAreCurrent([binding]) else { return false }
            return hit.viaLink.map { library.availability(of: $0) == nil } ?? true
        }
        let ids = Set(valid.compactMap { $0.pageBinding.map(KnowledgePageGraph.nodeID) })
        let nodes = scene?.graph.nodes.filter { ids.contains($0.id) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let frame = ImageRegionCanvas.imageFrame(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, in: geometry.size)
                ZStack {
                    ImageRegionCanvas(image: image, region: region, onSelect: onSelect)
                    if let scene, let region, !nodes.isEmpty {
                        KnowledgeParticleView(field: scene.field, nodes: nodes, selectedID: selectedID,
                            spread: 1, pulses: !paused, reduceMotion: paused, tint: WorkspaceTheme.accent,
                            showsLabels: false, compact: true, growthByRecordID: scene.growthByRecordID,
                            regionTarget: region.displayed(in: frame), usesPhysicalAttraction: true,
                            motionSceneDigest: scene.motionID, onSelect: { selectedID = $0 })
                            .environment(\.companionParticleMotion, store.particleMotion)
                            .environment(\.companionParticleMotionEnabled, store.memoryParticleMotionEnabled)
                    }
                }.onAppear { canvas = geometry.size }
                    .onChange(of: geometry.size) { _, value in canvas = value }
            }.frame(height: 330)
            HStack {
                TextField("Find related memory", text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
                Button("Find", action: search).disabled(region == nil || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let scene, !nodes.isEmpty {
                HStack {
                    Text(nodes.first(where: { $0.id == selectedID })?.title ?? "Select a memory particle to inspect its source.")
                        .font(.caption).lineLimit(2)
                    Spacer()
                    Button(attractionLease == nil ? "Gather particles" : "Release particles") {
                        if attractionLease != nil { release() }
                        else {
                            store.desktopInterest.stopAttraction()
                            attractionLease = store.particleMotion.beginAttraction(sceneDigest: scene.motionID)
                            attractionScene = scene.motionID
                            updateAttraction()
                        }
                    }.disabled(paused)
                    Button("Inspect memory") { showsInspector = true }
                        .disabled(!nodes.contains(where: { $0.id == selectedID }))
                        .popover(isPresented: $showsInspector) {
                            CompanionGraphView(snapshot: scene.graph, onOpen: { _ in }, initialSelectionID: selectedID,
                                reduceMotion: true, particleScene: scene, allowsTargetNavigation: false)
                                .frame(width: 720, height: 500)
                        }
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.onChange(of: region) { _, _ in reset() }
            .onChange(of: image.id) { _, _ in reset() }
            .onChange(of: library.sources) { _, _ in reset() }
            .onChange(of: library.knowledgePages) { _, _ in reset() }
            .onChange(of: library.knowledgeLinks) { _, _ in reset() }
            .onChange(of: scene?.motionID) { _, _ in release() }
            .onChange(of: paused) { _, value in if value { release() } }
            .onDisappear { release() }
            .background(ParticlePresentationVisibility { if !$0 { release() } }.frame(width: 0, height: 0))
            .task {
                while !Task.isCancelled {
                    updateAttraction()
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
    }
    private func release() {
        if let attractionLease { store.particleMotion.endAttraction(lease: attractionLease) }
        attractionLease = nil; attractionScene = nil
    }
    private func updateAttraction() {
        guard let attractionLease, let attractionScene else { return }
        guard !paused, let region, let scene = store.companionParticleScene(), scene.motionID == attractionScene else { release(); return }
        let ids = Set(hits.compactMap { hit -> String? in
            guard let binding = hit.pageBinding, store.knowledgeDependenciesAreCurrent([binding]),
                  hit.viaLink.map({ library.availability(of: $0) == nil }) ?? true else { return nil }
            return KnowledgePageGraph.nodeID(binding)
        })
        let frame = ImageRegionCanvas.imageFrame(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, in: canvas)
        let offsets = ParticleAttractionProjection.offsets(scene: scene, canvas: canvas,
            target: region.displayed(in: frame)).filter { ids.contains($0.key) }
        guard !offsets.isEmpty, store.particleMotion.updateAttraction(lease: attractionLease,
            sceneDigest: attractionScene, offsets: offsets, time: ProcessInfo.processInfo.systemUptime) else { release(); return }
    }
    private func reset() { release(); hits = []; selectedID = nil; message = nil; showsInspector = false }
    private func search() {
        guard region != nil else { return }
        do {
            let result = try KnowledgeRetrieval.search(query: query, sources: library.sources,
                pages: library.knowledgePages, links: library.knowledgeLinks,
                libraryIsCurrent: library.isCurrentOnDisk, maximumResults: 6, pagesOnly: true)
            let nextHits = result.hits.filter { $0.pageBinding != nil }
            if nextHits.map(\.id) != hits.map(\.id) { release() }
            hits = nextHits; selectedID = nil
            message = hits.isEmpty ? "No reviewed concepts matched. Your existing memories are unchanged."
                : "\(hits.count) concept matches · select to inspect · no connection saved"
        } catch { reset(); message = error.localizedDescription }
    }
}
