import SwiftUI

enum CompanionGraphLayout: String, CaseIterable, Identifiable {
    case particles = "Particles"
    case constellation = "Constellation"
    case radial = "Radial"
    case flow = "Flow"
    var id: String { rawValue }
}

/// View-local navigation over recorded edges. It neither infers relationships
/// nor adds a second graph owner. The focus anchor remains visible while search
/// and type filters narrow its direct neighbours.
enum CompanionGraphNavigation {
    enum Direction: String { case incoming, outgoing }

    static func visibleNodes(in snapshot: CompanionGraphSnapshot, query: String,
                             kindFilter: CompanionGraphKind?, focusID: String?) -> [CompanionGraphNode] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Set(snapshot.nodes.map(\.id))
        let anchor = focusID.flatMap { ids.contains($0) ? $0 : nil }
        var neighbourhood: Set<String> = []
        if let anchor {
            neighbourhood.insert(anchor)
            for edge in snapshot.edges where ids.contains(edge.source) && ids.contains(edge.target) {
                if edge.source == anchor { neighbourhood.insert(edge.target) }
                if edge.target == anchor { neighbourhood.insert(edge.source) }
            }
        }
        return snapshot.nodes.filter { node in
            if node.id == anchor { return true }
            return (anchor == nil || neighbourhood.contains(node.id))
                && (kindFilter == nil || node.kind == kindFilter)
                && (search.isEmpty || ([node.title, node.subtitle, node.status, node.kind.title]
                    + node.details.flatMap { [$0.label, $0.value] }).contains { $0.localizedStandardContains(search) })
        }
    }

    static func links(for nodeID: String, in snapshot: CompanionGraphSnapshot,
                      direction: Direction) -> [CompanionGraphEdge] {
        let ids = Set(snapshot.nodes.map(\.id))
        guard ids.contains(nodeID) else { return [] }
        return snapshot.edges.filter {
            ids.contains($0.source) && ids.contains($0.target)
                && (direction == .incoming ? $0.target == nodeID : $0.source == nodeID)
        }.sorted { $0.id < $1.id }
    }

    static func retainedSelection(_ selectedID: String?, in nodes: [CompanionGraphNode]) -> String? {
        selectedID.flatMap { id in nodes.contains { $0.id == id } ? id : nil }
    }

    enum SelectionVisibility: Equatable { case none, visible, hidden, unavailable }
    static func selectionVisibility(_ selectedID: String?, in snapshot: CompanionGraphSnapshot,
                                    visibleNodes: [CompanionGraphNode]) -> SelectionVisibility {
        guard let selectedID else { return .none }
        guard snapshot.nodes.contains(where: { $0.id == selectedID }) else { return .unavailable }
        return visibleNodes.contains(where: { $0.id == selectedID }) ? .visible : .hidden
    }

    /// Back restores the inspected record as well as its focus, without retaining
    /// a copy of the record or silently following a replacement version.
    struct Location: Equatable {
        let focusID: String?
        let selectedID: String?
    }
    static func retainedLocation(_ location: Location, in snapshot: CompanionGraphSnapshot) -> Location? {
        if let focus = location.focusID, !snapshot.nodes.contains(where: { $0.id == focus }) { return nil }
        return .init(focusID: location.focusID, selectedID: retainedSelection(location.selectedID, in: snapshot.nodes))
    }
}

/// Deterministic presentation geometry. Positions never become companion state.
struct CompanionGraphGeometry {
    struct GroupLabel {
        let kind: CompanionGraphKind
        let count: Int
        let position: CGPoint
    }

    static let nodeSize = CGSize(width: 154, height: 76)
    let size: CGSize
    let positions: [String: CGPoint]
    let groups: [GroupLabel]
    let ringCenter: CGPoint?
    let radii: [CGFloat]

    func fittedScale(in viewport: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0, size.width > 0, size.height > 0 else { return 1 }
        // A dense snapshot must still fit; a readability floor would crop real nodes.
        return min(1, max(1, viewport.width - 20) / size.width, max(1, viewport.height - 20) / size.height)
    }

    static func make(nodes: [CompanionGraphNode], edges: [CompanionGraphEdge], layout: CompanionGraphLayout) -> Self {
        guard !nodes.isEmpty else {
            return Self(size: CGSize(width: 680, height: 360), positions: [:], groups: [], ringCenter: nil, radii: [])
        }
        let kinds = CompanionGraphKind.allCases.filter { kind in nodes.contains { $0.kind == kind } }
        var points: [String: CGPoint] = [:]
        var labels: [GroupLabel] = []
        var center: CGPoint?
        var rings: [CGFloat] = []

        switch layout {
        case .flow:
            for (column, kind) in kinds.enumerated() {
                let members = nodes.filter { $0.kind == kind }
                let x = CGFloat(column) * 212
                labels.append(GroupLabel(kind: kind, count: members.count, position: CGPoint(x: x, y: -76)))
                for (row, node) in members.enumerated() {
                    points[node.id] = CGPoint(x: x, y: CGFloat(row) * 102)
                }
            }
        case .particles, .constellation:
            let satelliteKinds = kinds.filter { $0 != .companion }
            let dimensions: [CompanionGraphKind: CGSize] = Dictionary(uniqueKeysWithValues: kinds.map { kind in
                let count = nodes.filter { $0.kind == kind }.count
                let columns = min(4, max(1, Int(ceil(sqrt(Double(count))))))
                let rows = Int(ceil(Double(count) / Double(columns)))
                return (kind, CGSize(width: CGFloat(columns) * 176, height: CGFloat(rows) * 98 + 40))
            })
            let largestSpan = dimensions.values.map { hypot($0.width, $0.height) }.max() ?? 176
            let rootSize = dimensions[.companion] ?? .zero
            let rootSpan = hypot(rootSize.width, rootSize.height)
            let spacingRadius = (largestSpan + 60) / (2 * sin(.pi / CGFloat(max(2, satelliteKinds.count))))
            let radius = max(220, max(spacingRadius, (largestSpan + rootSpan) / 2 + 64))
            for kind in kinds {
                let members = nodes.filter { $0.kind == kind }
                let dimensions = dimensions[kind] ?? .zero
                let columns = min(4, max(1, Int(ceil(sqrt(Double(members.count))))))
                var origin = CGPoint.zero
                if let index = satelliteKinds.firstIndex(of: kind) {
                    let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(max(1, satelliteKinds.count))
                    origin = CGPoint(x: cos(angle) * radius * 1.12, y: sin(angle) * radius)
                }
                labels.append(GroupLabel(kind: kind, count: members.count,
                    position: CGPoint(x: origin.x, y: origin.y - dimensions.height / 2 - 14)))
                for (index, node) in members.enumerated() {
                    let column = index % columns
                    let row = index / columns
                    points[node.id] = CGPoint(x: origin.x + CGFloat(column) * 176 - dimensions.width / 2 + 88,
                        y: origin.y + CGFloat(row) * 98 - dimensions.height / 2 + 64)
                }
            }
        case .radial:
            let root = nodes.first(where: { $0.kind == .companion }) ?? nodes[0]
            let nodeIDs = Set(nodes.map(\.id))
            var neighbours: [String: Set<String>] = [:]
            for edge in edges where nodeIDs.contains(edge.source) && nodeIDs.contains(edge.target) {
                neighbours[edge.source, default: []].insert(edge.target)
                neighbours[edge.target, default: []].insert(edge.source)
            }
            var distances = [root.id: 0]
            var queue = [root.id]
            var cursor = 0
            while cursor < queue.count {
                let id = queue[cursor]
                cursor += 1
                for next in (neighbours[id] ?? []).sorted() where distances[next] == nil {
                    distances[next] = (distances[id] ?? 0) + 1
                    queue.append(next)
                }
            }
            let disconnectedDepth = (distances.values.max() ?? 0) + 1
            for node in nodes where distances[node.id] == nil { distances[node.id] = disconnectedDepth }
            points[root.id] = .zero
            center = .zero
            var previousRadius: CGFloat = 0
            let maximumDepth = distances.values.max() ?? 0
            if maximumDepth > 0 {
                for depth in 1...maximumDepth {
                    let members = nodes.filter { distances[$0.id] == depth }
                    guard !members.isEmpty else { continue }
                    let radius = max(previousRadius + 172, CGFloat(members.count) * 186 / (2 * .pi))
                    rings.append(radius)
                    for (index, node) in members.enumerated() {
                        let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(members.count)
                        points[node.id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                    }
                    previousRadius = radius
                }
            }
        }

        let allPoints = Array(points.values) + labels.map(\.position)
        let minX = (allPoints.map(\.x).min() ?? 0) - 108
        let maxX = (allPoints.map(\.x).max() ?? 0) + 108
        let minY = (allPoints.map(\.y).min() ?? 0) - 60
        let maxY = (allPoints.map(\.y).max() ?? 0) + 70
        let size = CGSize(width: max(520, maxX - minX), height: max(330, maxY - minY))
        let shift = CGPoint(x: -minX + (size.width - (maxX - minX)) / 2,
            y: -minY + (size.height - (maxY - minY)) / 2)
        func shifted(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + shift.x, y: point.y + shift.y) }
        return Self(size: size, positions: points.mapValues(shifted),
            groups: labels.map { GroupLabel(kind: $0.kind, count: $0.count, position: shifted($0.position)) },
            ringCenter: center.map(shifted), radii: rings)
    }
}

@MainActor
struct CompanionGraphView: View {
    let snapshot: CompanionGraphSnapshot
    let onOpen: (CompanionGraphTarget) -> Void
    var allowsTargetNavigation = true
    var reduceMotion = false
    var seedColor: CompanionSeedColor = .original
    var onAsk: ((CompanionGraphNode) -> Void)?
    var canAsk: (CompanionGraphNode) -> Bool = { _ in false }
    var lightExpression: KinLightExpression = .resting
    var preparedNodeIDs: Set<String> = []
    var requestNodeIDs: Set<String> = []
    var particleScene: CompanionParticleScene?
    var seedAppearance: CompanionParticleAppearance?
    var liminalGraphSource: LiminalGraphMorphSource?
    var selectionID: String?
    var onSelectionChange: ((String?) -> Bool)?
    var onCreateMethod: ((CompanionGraphNode) -> Void)?
    var onPlayNote: ((CompanionGraphNode) -> Void)?
    var canPlayNote: (CompanionGraphNode) -> Bool = { _ in false }
    var canCreateMethod: (CompanionGraphNode) -> Bool = { _ in false }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var localSelectionID: String?
    @State private var selectionNotice: String?
    @State private var query = ""
    @State private var kindFilter: CompanionGraphKind?
    @State private var layout = CompanionGraphLayout.constellation
    @State private var showsList = false
    @State private var focusID: String?
    @State private var focusHistory: [CompanionGraphNavigation.Location] = []
    @State private var zoom: CGFloat = 1
    @State private var fitRevision = 0
    // One presentation coordinate: Seed (-1), memory map (0), QiMon body (1).
    @State private var formProgress = 0.0
    @State private var particlePulses = true
    @State private var particleExportMessage: String?
    @State private var isShowcase = false
    @State private var showsViewOptions = false
    @State private var particleField: KnowledgeParticleField?

    init(snapshot: CompanionGraphSnapshot, onOpen: @escaping (CompanionGraphTarget) -> Void,
         initialLayout: CompanionGraphLayout = .particles, initialSelectionID: String? = nil,
         reduceMotion: Bool = false, seedColor: CompanionSeedColor = .original,
         initialShowcase: Bool = false,
         onAsk: ((CompanionGraphNode) -> Void)? = nil,
         canAsk: @escaping (CompanionGraphNode) -> Bool = { _ in false },
         lightExpression: KinLightExpression = .resting, preparedNodeIDs: Set<String> = [], requestNodeIDs: Set<String> = [],
         onCreateMethod: ((CompanionGraphNode) -> Void)? = nil,
         canCreateMethod: @escaping (CompanionGraphNode) -> Bool = { _ in false },
         particleScene: CompanionParticleScene? = nil,
         seedAppearance: CompanionParticleAppearance? = nil,
         liminalGraphSource: LiminalGraphMorphSource? = nil,
         selectionID: String? = nil,
         onSelectionChange: ((String?) -> Bool)? = nil,
         allowsTargetNavigation: Bool = true,
         onPlayNote: ((CompanionGraphNode) -> Void)? = nil,
         canPlayNote: @escaping (CompanionGraphNode) -> Bool = { _ in false }) {
        self.snapshot = snapshot
        self.onOpen = onOpen
        self.reduceMotion = reduceMotion; self.seedColor = seedColor
        self.onAsk = onAsk; self.canAsk = canAsk
        self.lightExpression = lightExpression; self.preparedNodeIDs = preparedNodeIDs
        self.requestNodeIDs = requestNodeIDs
        self.onCreateMethod = onCreateMethod; self.canCreateMethod = canCreateMethod
        self.particleScene = particleScene; self.seedAppearance = seedAppearance
        self.liminalGraphSource = liminalGraphSource
        self.selectionID = selectionID; self.onSelectionChange = onSelectionChange
        self.allowsTargetNavigation = allowsTargetNavigation
        self.onPlayNote = onPlayNote; self.canPlayNote = canPlayNote
        _layout = State(initialValue: initialLayout)
        _localSelectionID = State(initialValue: initialSelectionID)
        _isShowcase = State(initialValue: initialShowcase)
    }

    // The installed workspace uses the native owner. Standalone previews and
    // existing diagnostic callers can still opt into view-local selection.
    private var selectedID: String? { onSelectionChange == nil ? localSelectionID : selectionID }

    private var visibleNodes: [CompanionGraphNode] {
        CompanionGraphNavigation.visibleNodes(in: snapshot, query: query, kindFilter: kindFilter, focusID: focusID)
    }

    private var visibleEdges: [CompanionGraphEdge] {
        let ids = Set(visibleNodes.map(\.id))
        return snapshot.edges.filter { ids.contains($0.source) && ids.contains($0.target) }
    }

    // Keep only an ID in view state: replacement/removal immediately changes the inspector.
    private var selectedNode: CompanionGraphNode? { snapshot.nodes.first { $0.id == selectedID } }
    private var selectionVisibility: CompanionGraphNavigation.SelectionVisibility {
        CompanionGraphNavigation.selectionVisibility(selectedID, in: snapshot, visibleNodes: visibleNodes)
    }
    private var focusNode: CompanionGraphNode? { snapshot.nodes.first { $0.id == focusID } }
    private var hasFilters: Bool { !query.isEmpty || kindFilter != nil || focusID != nil }
    private var showsInspector: Bool { selectedNode != nil }
    private var particleSpread: Double { min(1, max(0, formProgress + 1)) }

    var body: some View {
        let topology = KnowledgeParticleField.topology(of: snapshot)
        return GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    if !isShowcase { filters }
                    else if hasFilters { showcaseFilterSummary }
                    selectionStatus
                    if viewport.size.width >= 700 {
                        let graphHeight = max(280, viewport.size.height - (isShowcase ? 160 : 250))
                        HStack(alignment: .top, spacing: 12) {
                            graphCard(height: graphHeight)
                            if showsInspector {
                                ScrollView { inspector }
                                    .frame(width: 252, height: graphHeight + 78, alignment: .top)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .id(selectedID)
                                    .accessibilityIdentifier("companion-graph.inspector-scroll")
                            }
                        }
                    } else {
                        graphCard(height: showsInspector ? max(280, min(400, viewport.size.height * 0.57))
                            : max(280, viewport.size.height - (isShowcase ? 160 : 250)))
                        if showsInspector { inspector }
                    }
                }
                .padding(16)
                .frame(maxWidth: 1500, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onChange(of: topology, initial: true) { _, value in
            // Titles, typing, activity and filters do not rerun force relaxation.
            particleField = KnowledgeParticleField(topology: value)
        }
        .onChange(of: snapshot, initial: true) { _, value in
            revalidateSelection()
            let ids = Set(value.nodes.map(\.id))
            if let focusID, !ids.contains(focusID) { self.focusID = nil; fitRevision += 1 }
            focusHistory = focusHistory.compactMap { CompanionGraphNavigation.retainedLocation($0, in: value) }
        }
        .onChange(of: liminalGraphSource == nil) { _, unavailable in
            if unavailable && formProgress > 0 { formProgress = 0 }
        }
        .onChange(of: selectedID) { _, id in
            // An external receipt can request All activity while this child still
            // holds the previous Memory snapshot. Let its owner update the scope
            // before retiring a pick against a newly delivered snapshot.
            if let id, !snapshot.nodes.contains(where: { $0.id == id }) {
                selectionNotice = "The selected record is outside the current map scope."
            } else {
                selectionNotice = nil
                revalidateSelection()
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityIdentifier("companion-graph.workspace")
    }

    @ViewBuilder private var selectionStatus: some View {
        if selectionVisibility == .hidden {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("The selected record is outside this filter or focus. Its inspector remains open.", systemImage: "line.3.horizontal.decrease.circle")
                Spacer(minLength: 0)
                Button("Reveal selected record") { showAllRecords() }
                    .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("companion-graph.hidden-selection")
        } else if let selectionNotice {
            Text(selectionNotice).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("companion-graph.selection-notice")
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(focusNode?.title ?? "Your living memory")
                    .font(.system(size: 20, weight: .medium, design: .rounded)).lineLimit(1)
                Text("\(visibleNodes.count) of \(snapshot.nodes.count) records · \(visibleEdges.count) connections")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion-graph.counts")
            }
            Spacer(minLength: 8)
            Button { showsList.toggle() } label: {
                Label(showsList ? "Graph" : "List", systemImage: showsList ? "point.3.connected.trianglepath.dotted" : "list.bullet")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel(showsList ? "Show graph" : "Show accessible record list")
            .accessibilityIdentifier("companion-graph.list-toggle")
            Button {
                isShowcase.toggle()
                fitRevision += 1
            } label: {
                Label(isShowcase ? "Exit showcase" : "Showcase",
                    systemImage: isShowcase ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .tint(isShowcase ? WorkspaceTheme.accent : nil)
            .help(isShowcase ? "Return to map controls. Escape also exits showcase." : "Give the map more space. Select any record to inspect it.")
            .keyboardShortcut(isShowcase ? .cancelAction : nil)
            .accessibilityValue(isShowcase ? "On" : "Off")
            .accessibilityIdentifier("companion-graph.showcase")
        }
    }

    private var showcaseFilterSummary: some View {
        HStack(spacing: 8) {
            Label("Showing a filtered map", systemImage: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            if let focusNode { Text(focusNode.title).lineLimit(1) }
            Spacer(minLength: 0)
            Button("Show all records") {
                showAllRecords()
            }.buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .accessibilityIdentifier("companion-graph.showcase-filter-summary")
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { recordSearch.frame(minWidth: 130); recordTypePicker }
                VStack(alignment: .leading, spacing: 8) { recordSearch; recordTypePicker }
            }
            HStack(spacing: 10) {
                if !focusHistory.isEmpty {
                    Button("Back", systemImage: "chevron.left") { goBack() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("companion-graph.back")
                }
                Button("Focus connections", systemImage: "scope") {
                    if let selectedID { focus(on: selectedID) }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(selectedNode == nil || selectedID == focusID)
                .accessibilityLabel("Focus on selected record and its direct connections")
                .accessibilityIdentifier("companion-graph.focus-toggle")
                if focusID != nil {
                    Button { showAllRecords() } label: { Image(systemName: "arrow.up.backward") }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("Show all records").accessibilityLabel("Show all graph records")
                        .accessibilityIdentifier("companion-graph.all-records")
                }
            }
            if let focusNode {
                    Text("Direct connections to \(focusNode.title)")
                        .foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityIdentifier("companion-graph.focus-summary")
            } else {
                Text("Select a record to follow its connections.").foregroundStyle(.secondary)
            }
        }.font(.system(size: 12))
    }

    private var recordSearch: some View {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a record", text: $query).textFieldStyle(.plain)
                        .accessibilityLabel("Find a graph record").accessibilityIdentifier("companion-graph.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear graph search")
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var recordTypePicker: some View {
                Picker("Record type", selection: $kindFilter) {
                    Text("All types").tag(CompanionGraphKind?.none)
                    ForEach(CompanionGraphKind.allCases) { kind in
                        Text("\(kind.title) · \(snapshot.nodes.filter { $0.kind == kind }.count)")
                            .tag(Optional(kind))
                    }
                }
                .labelsHidden().frame(width: 160)
                .accessibilityLabel("Filter graph by record type").accessibilityIdentifier("companion-graph.type-filter")
    }

    private func graphCard(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(showsList ? "Connected records" : layout.rawValue,
                    systemImage: showsList ? "list.bullet" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                Spacer(minLength: 8)
                if !showsList {
                    Button("Fit map") { fitRevision += 1 }
                        .accessibilityLabel("Fit and center graph")
                        .accessibilityIdentifier("companion-graph.fit")
                }
                if !isShowcase {
                    Button { showsViewOptions.toggle() } label: {
                        Label("View options", systemImage: "slider.horizontal.3")
                    }
                    .help("Change this map's layout, zoom and particle presentation.")
                    .accessibilityValue(showsViewOptions ? "Open" : "Closed")
                    .accessibilityIdentifier("companion-graph.view-options")
                    .popover(isPresented: $showsViewOptions, arrowEdge: .bottom) { viewOptions }
                }
            }
            .controlSize(.small).buttonStyle(.borderless).padding(12)
            if let particleExportMessage {
                Text(particleExportMessage).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                    .accessibilityIdentifier("companion-graph.particle-export-status")
            }
            Divider().opacity(0.6)
            if layout == .particles && !showsList {
                HStack(spacing: 8) {
                    Label(lightExpression.label, systemImage: "sparkles")
                    Spacer(minLength: 0)
                    if !requestNodeIDs.isEmpty {
                        Label("\(requestNodeIDs.count) in this request", systemImage: "circle.circle")
                            .help("Double rings mark current records referenced by the running local request. They do not establish model attention, citations or helpful use.")
                    }
                    if !preparedNodeIDs.isEmpty {
                        Label("\(preparedNodeIDs.count) for next reply", systemImage: "circle.dashed")
                            .help("Dashed rings mark current records prepared as local reply context. Selection is not evidence that a model used them.")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 13).padding(.top, 8)
                .accessibilityIdentifier("companion-graph.particle-state")
            }
            if layout == .particles && !showsList && seedAppearance != nil {
                formControls
            }
            Group {
                if visibleNodes.isEmpty {
                    emptyGraph
                } else if showsList {
                    nodeList
                } else if layout == .particles {
                    particleSurface
                } else {
                    graphSurface
                }
            }.frame(height: height)
            Divider().opacity(0.6)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                Text(showsList ? "Select a record to inspect its source and connections." : layoutHint)
                Spacer(minLength: 0)
                if snapshot.truncatedCount > 0 {
                    Text("\(snapshot.truncatedCount) records outside this snapshot")
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 10)
        }
        .background {
            RadialGradient(colors: [seedColor.accent.opacity(0.06), .clear],
                center: .center, startRadius: 0, endRadius: 420)
        }
        .modifier(WorkspaceSurface(emphasis: isShowcase))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var formControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                formButton("Seed", symbol: "circle.dotted", value: -1)
                formButton("Memory map", symbol: "point.3.connected.trianglepath.dotted", value: 0)
                if liminalGraphSource != nil {
                    formButton("Liminal · QiMon", symbol: "pawprint", value: 1)
                }
            }
            Slider(value: $formProgress, in: -1...(liminalGraphSource == nil ? 0 : 1))
                .accessibilityLabel(liminalGraphSource == nil ? "Companion form: Seed to memory map"
                    : "Companion form: Seed through memory map to Liminal")
                .accessibilityValue(formProgress < -0.9 ? "Seed" : formProgress > 0.9 ? "Liminal"
                    : abs(formProgress) < 0.05 ? "Memory map" : "Memory unfolding")
                .accessibilityIdentifier("companion-graph.form-flow")
                .frame(maxWidth: 400)
        }
        .padding(.horizontal, 14).padding(.top, 9)
    }

    private func formButton(_ title: String, symbol: String, value: Double) -> some View {
        Button {
            withAnimation(reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 1.15)) {
                formProgress = value
            }
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(abs(formProgress - value) < 0.05 ? seedColor.accent.opacity(0.17) : .clear,
                    in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(abs(formProgress - value) < 0.05 ? [.isSelected] : [])
        .accessibilityIdentifier(value < 0 ? "companion-graph.seed-map" : value > 0
            ? "companion-graph.liminal-form" : "companion-graph.memory-form")
    }

    private var viewOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("View options").font(.system(size: 14, weight: .medium))
                Spacer()
                Button { showsViewOptions = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Close view options")
            }
            Picker("Layout", selection: $layout) {
                ForEach(CompanionGraphLayout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).disabled(showsList)
            .accessibilityIdentifier("companion-graph.layout")
            HStack(spacing: 10) {
                Text("Zoom")
                Spacer()
                Button { zoom = max(layout == .particles ? 1 : 0.005, zoom - 0.15) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(showsList || zoom <= (layout == .particles ? 1 : 0.005))
                .accessibilityLabel("Zoom out")
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 44)
                Button { zoom = min(layout == .particles ? 4 : 1.8, zoom + 0.15) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(showsList || zoom >= (layout == .particles ? 4 : 1.8))
                .accessibilityLabel("Zoom in")
            }
            if showsList {
                Text("Switch to Graph to adjust its presentation.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if layout == .particles {
                Divider()
                if liminalGraphSource == nil {
                    Toggle("Pulse particles", isOn: $particlePulses).toggleStyle(.checkbox)
                        .accessibilityIdentifier("companion-graph.particle-pulse")
                }
                if reduceMotion || systemReduceMotion {
                    Text("Reduce Motion keeps the map still.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Divider()
                Button("Export for Houdini…") {
                    showsViewOptions = false
                    do {
                        let data = try KnowledgeParticleExport(field: KnowledgeParticleField(snapshot: snapshot)).data()
                        particleExportMessage = nil
                        KnowledgeParticleExportPanel.save(data) { particleExportMessage = $0 }
                    } catch { particleExportMessage = "The particle map could not be prepared." }
                }
                .help("Export the bounded full snapshot as IDs, types, positions and recorded edges. No source text or titles.")
                .accessibilityIdentifier("companion-graph.particle-export")
            }
        }
        .font(.system(size: 12)).controlSize(.small)
        .padding(18).frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion-graph.view-options-panel")
    }

    private var layoutHint: String {
        switch layout {
        case .particles: "One companion, the same memories in every form. Select a light to inspect its source; gold satellites mark reviewed helpful use."
        case .constellation: "Grouped by type. Select a record; scroll or zoom to explore."
        case .radial: "Rings follow recorded links from the companion; unlinked records sit outside."
        case .flow: "Columns group record types. Arrows show recorded direction."
        }
    }

    private var particleSurface: some View {
        return GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView([.horizontal, .vertical]) {
                    if let field = particleScene?.field ?? particleField {
                        ZStack {
                        if let source = liminalGraphSource {
                            LiminalGraphMorphView(source: source, graph: snapshot, field: field,
                                nodes: visibleNodes, selectedID: selectedID, progress: formProgress,
                                reduceMotion: reduceMotion || systemReduceMotion, seedColor: seedColor,
                                focusIDs: focusID == nil ? nil : Set(CompanionGraphNavigation.visibleNodes(in: snapshot,
                                    query: "", kindFilter: nil, focusID: focusID).map(\.id)),
                                growthByRecordID: particleScene?.growthByRecordID ?? [:], preparedIDs: preparedNodeIDs,
                                requestIDs: requestNodeIDs,
                                expression: lightExpression, seedAppearance: seedAppearance,
                                onSelect: { selectNode($0) })
                        } else {
                        if let seedAppearance {
                            seedAppearance.art(size: min(viewport.size.width, viewport.size.height),
                                reduceMotion: reduceMotion || systemReduceMotion)
                                .opacity(max(0, 1 - particleSpread * 1.6))
                                .animation(reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.65), value: particleSpread)
                        }
                        KnowledgeParticleView(field: field, nodes: visibleNodes, selectedID: selectedID,
                            spread: particleSpread, pulses: particlePulses, reduceMotion: reduceMotion || systemReduceMotion,
                            tint: seedColor.accent, expression: lightExpression, preparedIDs: preparedNodeIDs,
                            requestIDs: requestNodeIDs,
                            focusIDs: focusID == nil ? nil : Set(CompanionGraphNavigation.visibleNodes(in: snapshot,
                                query: "", kindFilter: nil, focusID: focusID).map(\.id)),
                            compact: seedAppearance != nil && particleSpread == 0,
                            growthByRecordID: particleScene?.growthByRecordID ?? [:],
                            onSelect: { selectNode($0) })
                            .animation(reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.65), value: particleSpread)
                        }
                        }
                            .frame(width: max(viewport.size.width, viewport.size.width * zoom),
                                   height: max(viewport.size.height, viewport.size.height * zoom))
                            .overlay { Color.clear.frame(width: 1, height: 1).id("particle-center").allowsHitTesting(false) }
                    }
                }
                .onAppear { zoom = 1 }
                .onChange(of: fitRevision) { _, _ in zoom = 1; scroll.scrollTo("particle-center", anchor: .center) }
            }
        }
    }

    private var graphSurface: some View {
        let nodes = visibleNodes
        let edges = visibleEdges
        // Filtering hides nodes without moving their neighbours. Only an
        // explicit focus change selects a smaller layout neighborhood.
        let layoutNodes = CompanionGraphNavigation.visibleNodes(in: snapshot,
            query: "", kindFilter: nil, focusID: focusID)
        let geometry = CompanionGraphGeometry.make(nodes: layoutNodes, edges: snapshot.edges, layout: layout)
        return GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        GraphConnections(nodes: nodes, edges: edges, geometry: geometry, selectedID: selectedID)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        ForEach(nodes) { node in
                            if let position = geometry.positions[node.id] {
                                GraphNodeButton(node: node, selected: selectedID == node.id) { selectNode(node.id) }
                                    .position(position)
                            }
                        }
                        Color.clear.frame(width: 1, height: 1)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .id("graph-center")
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom, alignment: .topLeading)
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
                }
                .background(GraphGrid().accessibilityHidden(true))
                .onAppear { fitGraph(in: viewport.size, geometry: geometry); scroll.scrollTo("graph-center", anchor: .center) }
                .onChange(of: fitRevision) { _, _ in
                    fitGraph(in: viewport.size, geometry: geometry)
                    scroll.scrollTo("graph-center", anchor: .center)
                }
                .onChange(of: layout) { _, _ in
                    fitGraph(in: viewport.size, geometry: geometry)
                    scroll.scrollTo("graph-center", anchor: .center)
                }
                .onChange(of: zoom) { _, _ in scroll.scrollTo("graph-center", anchor: .center) }
                .onChange(of: viewport.size) { _, size in
                    fitGraph(in: size, geometry: geometry)
                }
            }
        }.accessibilityIdentifier("companion-graph.canvas")
    }

    private func fitGraph(in viewport: CGSize, geometry: CompanionGraphGeometry) {
        zoom = geometry.fittedScale(in: viewport)
    }

    private var nodeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleNodes) { node in
                    Button { selectNode(node.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: node.kind.symbol).foregroundStyle(graphColor(node.kind))
                                .frame(width: 20).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.title).font(.system(size: 13, weight: .medium))
                                Text(node.subtitle.isEmpty ? node.kind.title : node.subtitle)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if selectedID == node.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(graphColor(node.kind))
                            }
                        }
                        .padding(13).contentShape(Rectangle())
                        .background(selectedID == node.id ? graphColor(node.kind).opacity(0.09) : .clear)
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(node.kind.title): \(node.title). \(node.subtitle)")
                    .accessibilityAddTraits(selectedID == node.id ? [.isSelected] : [])
                    .accessibilityIdentifier("companion-graph.list-node.\(node.id)")
                    Divider().opacity(0.4)
                }
            }
        }.accessibilityIdentifier("companion-graph.node-list")
    }

    private var emptyGraph: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 32, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
            Text(snapshot.nodes.isEmpty ? "Connections will appear here" : "No matching records")
                .font(.system(size: 16, weight: .medium, design: .rounded))
            Text(snapshot.nodes.isEmpty ? "This view follows the companion’s available records." : "Try another search or show all types.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !snapshot.nodes.isEmpty {
                Button("Clear filters") { query = ""; kindFilter = nil }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        WorkspaceCard(inset: 18) {
            if let node = selectedNode {
                let references = node.details.filter(Self.isReferenceDetail)
                let primary = Self.primaryDetails(node.details)
                let subtitleIsReference = references.contains { $0.value == node.subtitle }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: node.kind.symbol).font(.system(size: 19))
                        .foregroundStyle(graphColor(node.kind)).padding(9)
                        .background(graphColor(node.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.kind.title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(graphColor(node.kind))
                        Text(node.title).font(.system(size: 17, weight: .medium, design: .rounded))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if updateSelection(nil), focusID != nil { showAllRecords() }
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Clear selected record")
                }
                if !node.subtitle.isEmpty && !subtitleIsReference {
                    Text(node.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !node.status.isEmpty {
                    Label(node.status, systemImage: node.presentationState.symbol)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(graphColor(node.kind)).padding(.vertical, 4)
                }
                resonanceInspector(node)
                if allowsTargetNavigation, let target = node.target {
                    Button(openTitle(target), systemImage: "arrow.up.right") { onOpen(target) }
                        .buttonStyle(.bordered).controlSize(.small).padding(.vertical, 5)
                        .accessibilityIdentifier("companion-graph.open-target")
                }
                if let onAsk, canAsk(node) {
                    Button("Ask about this", systemImage: "bubble.left.and.bubble.right") { onAsk(node) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .help("Attach this exact reviewed page to local chat. Review your question before sending.")
                        .accessibilityIdentifier("companion-graph.ask-about")
                }
                if let onCreateMethod, canCreateMethod(node) {
                    Button("Create a method…", systemImage: "arrow.triangle.branch") { onCreateMethod(node) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Author an untested document method linked to this exact reviewed concept.")
                        .accessibilityIdentifier("companion-graph.create-method")
                }
                if !node.evidenceTrail.isEmpty {
                    Divider().padding(.vertical, 5)
                    CompanionGraphEvidenceView(trail: node.evidenceTrail, snapshot: snapshot) {
                        selectNode($0, clearFilters: true)
                    }.id(node.id)
                }
                if !primary.isEmpty {
                    Divider().padding(.vertical, 5)
                    inspectorDetails(primary)
                }
                if !references.isEmpty {
                    DisclosureGroup("Reference identifiers") {
                        inspectorDetails(references).padding(.top, 6)
                    }
                    .font(.system(size: 11)).padding(.top, 8).id(node.id)
                    .accessibilityIdentifier("companion-graph.reference-identifiers")
                }
                selectedConnections(node)
            } else {
                Label("Inspect a record", systemImage: "scope")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(WorkspaceTheme.accent)
                Text("Select a record to see its source, status and recorded relationships.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                Text("The graph reflects available records. Arrangement and distance do not measure importance or certainty.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion-graph.inspector")
    }

    private func resonanceInspector(_ node: CompanionGraphNode) -> some View {
        let voice = CompanionResonance.forKind(node.kind)
        return DisclosureGroup("Sound & signal · \(voice.noteName)") {
            VStack(alignment: .leading, spacing: 7) {
                Text("\(voice.brainwaveBand.title) · \(voice.noteName) · \(voice.frequencyHz, specifier: "%.1f") Hz audio")
                    .font(.system(size: 11, weight: .medium))
                Text(CompanionResonance.associationExplanation)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let onPlayNote {
                    Button("Hear this note", systemImage: "speaker.wave.2") { onPlayNote(node) }
                        .controlSize(.small).disabled(!canPlayNote(node))
                        .help("Uses your existing Musical light cues and volume settings. Quiet mode silences it.")
                        .accessibilityIdentifier("companion-graph.hear-note")
                }
            }.padding(.top, 7)
        }.font(.system(size: 11)).padding(.vertical, 5)
    }

    private func inspectorDetails(_ details: [CompanionGraphDetail]) -> some View {
        ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(detail.value).font(.system(size: 12)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 3)
        }
    }

    static func isReferenceDetail(_ detail: CompanionGraphDetail) -> Bool {
        let label = detail.label.lowercased()
        return label.hasSuffix(" id") || label.hasSuffix(" ids") || label.contains("digest")
            || label.contains("revision") || label.contains("reference") || label == "contract"
            || label.hasSuffix(" hash") || label == "sha-256" || label == "utf-16 range" || label == "bound source"
    }

    static func primaryDetails(_ details: [CompanionGraphDetail]) -> [CompanionGraphDetail] {
        let priority = ["Your note", "Your kept words", "Excerpt", "Outcome", "Scope", "Access scope", "Meaning", "Content", "Retention"]
        return details.enumerated().filter { !isReferenceDetail($0.element) }.sorted { left, right in
            let leftRank = priority.firstIndex(of: left.element.label) ?? priority.count
            let rightRank = priority.firstIndex(of: right.element.label) ?? priority.count
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
    }

    @ViewBuilder private func selectedConnections(_ node: CompanionGraphNode) -> some View {
        Divider().padding(.vertical, 5)
        connectionGroup(node, direction: .incoming)
        connectionGroup(node, direction: .outgoing)
    }

    private func connectionGroup(_ node: CompanionGraphNode, direction: CompanionGraphNavigation.Direction) -> some View {
        let links = CompanionGraphNavigation.links(for: node.id, in: snapshot, direction: direction)
        let title = direction == .incoming ? "Incoming links · Backlinks" : "Outgoing links"
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(title) · \(links.count)")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if links.isEmpty {
                Text(direction == .incoming ? "No incoming links in this map." : "No outgoing links in this map.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(links.prefix(8)) { connectionButton($0, direction: direction) }
            if links.count > 8 {
                DisclosureGroup("\(links.count - 8) more links") {
                    ForEach(links.dropFirst(8)) { connectionButton($0, direction: direction) }
                }
                .font(.system(size: 11)).id("\(node.id)-\(direction.rawValue)")
                .accessibilityIdentifier("companion-graph.more-links.\(direction.rawValue)")
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion-graph.links.\(direction.rawValue)")
    }

    @ViewBuilder private func connectionButton(_ edge: CompanionGraphEdge, direction: CompanionGraphNavigation.Direction) -> some View {
        let otherID = direction == .incoming ? edge.source : edge.target
        if let source = snapshot.nodes.first(where: { $0.id == edge.source }),
           let target = snapshot.nodes.first(where: { $0.id == edge.target }) {
            CompanionGraphConnectionView(edge: edge, source: source, target: target,
                incoming: direction == .incoming) { selectNode(otherID, clearFilters: true) }
        }
    }

    @discardableResult private func updateSelection(_ id: String?) -> Bool {
        if let onSelectionChange {
            guard onSelectionChange(id) else {
                selectionNotice = "That record changed before it could be selected. Select its current version again."
                return false
            }
        } else {
            localSelectionID = id
        }
        selectionNotice = nil
        return true
    }

    private func revalidateSelection() {
        guard let selectedID else { return }
        guard snapshot.nodes.contains(where: { $0.id == selectedID }) else {
            if updateSelection(nil) {
                selectionNotice = "The selected record is no longer available in this map. No replacement was selected."
            }
            return
        }
        // Refresh the shared pick against this exact displayed snapshot. The
        // owner rejects stale scope/profile bindings; record IDs are never guessed.
        if onSelectionChange != nil { _ = updateSelection(selectedID) }
    }

    private func selectNode(_ id: String, clearFilters: Bool = false) {
        guard snapshot.nodes.contains(where: { $0.id == id }) else { return }
        let accepted = focusID != nil && focusID != id ? focus(on: id) : updateSelection(id)
        guard accepted else { return }
        if clearFilters { query = ""; kindFilter = nil }
    }

    @discardableResult private func focus(on id: String) -> Bool {
        guard id != focusID, snapshot.nodes.contains(where: { $0.id == id }) else { return false }
        let previous = CompanionGraphNavigation.Location(focusID: focusID, selectedID: selectedID)
        guard updateSelection(id) else { return false }
        focusHistory.append(previous)
        if focusHistory.count > 32 { focusHistory.removeFirst() }
        focusID = id
        fitRevision += 1
        return true
    }

    private func goBack() {
        guard let previous = focusHistory.last,
              let retained = CompanionGraphNavigation.retainedLocation(previous, in: snapshot),
              updateSelection(retained.selectedID) else { return }
        focusHistory.removeLast()
        focusID = retained.focusID
        query = ""; kindFilter = nil
        fitRevision += 1
    }

    private func showAllRecords() {
        query = ""; kindFilter = nil; focusID = nil
        focusHistory.removeAll()
        fitRevision += 1
    }

    private func openTitle(_ target: CompanionGraphTarget) -> String {
        switch target {
        case .assistant: "Open " + AskARCHiBrand.title
        case .context: "Open shared context"
        case .memory: "Manage memories"
        case .knowledgePage: "Inspect this page version"
        case .readingSource: "Inspect this source version"
        case .documentMethod: "Inspect this method version"
        case .advanced: "Open local receipts"
        case .capabilities: "Open ARC"
        case .interactiveARC: "Open ARC3 episode"
        case .arcEvidence: "Open this ARC receipt"
        case .steward: "Open Usage"
        case .stewardTask: "Open this run in Usage"
        }
    }
}

func graphColor(_ kind: CompanionGraphKind) -> Color {
    switch kind {
    case .companion: Color.teal
    case .source: Color.blue
    case .knowledge: Color.pink
    case .lesson: WorkspaceTheme.accent
    case .method: Color.orange
    case .request: Color.indigo
    case .invocation: Color.purple
    case .answer: Color.teal
    case .context: Color.cyan
    case .omission: Color.orange
    case .evaluation: Color.mint
    case .accounting: Color.yellow
    }
}

private struct GraphNodeButton: View {
    let node: CompanionGraphNode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: node.kind.symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(graphColor(node.kind)).frame(width: 20).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(node.subtitle.isEmpty ? node.kind.title : node.subtitle)
                        .font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11).frame(width: CompanionGraphGeometry.nodeSize.width, height: CompanionGraphGeometry.nodeSize.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            .background(graphColor(node.kind).opacity(selected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(graphColor(node.kind).opacity(selected ? 0.95 : 0.40), lineWidth: selected ? 2 : 1))
            .shadow(color: graphColor(node.kind).opacity(selected ? 0.16 : 0.06), radius: selected ? 11 : 5, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .help("\(node.title)\n\(node.subtitle)")
        .accessibilityLabel("\(node.kind.title): \(node.title). \(node.subtitle). \(node.status)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Select to inspect this record and its relationships")
        .accessibilityIdentifier("companion-graph.node.\(node.id)")
    }
}

private struct GraphGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 24) {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.primary.opacity(0.045)), lineWidth: 0.5)
        }
    }
}

private struct GraphConnections: View {
    let nodes: [CompanionGraphNode]
    let edges: [CompanionGraphEdge]
    let geometry: CompanionGraphGeometry
    let selectedID: String?

    var body: some View {
        Canvas { context, _ in
            for group in geometry.groups {
                let glow = CGRect(x: group.position.x - 150, y: group.position.y - 45, width: 300, height: 190)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [graphColor(group.kind).opacity(0.09), .clear]),
                    center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 10, endRadius: 150))
                let title = Text("\(group.kind.title.uppercased()) · \(group.count)")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(graphColor(group.kind))
                context.draw(title, at: group.position)
            }
            if let center = geometry.ringCenter {
                for radius in geometry.radii {
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                }
            }
            let kinds = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.kind) })
            for edge in edges {
                guard let source = geometry.positions[edge.source], let target = geometry.positions[edge.target], source != target else { continue }
                let dx = target.x - source.x
                let dy = target.y - source.y
                let distance = max(1, hypot(dx, dy))
                let trim = min(CompanionGraphGeometry.nodeSize.width / 2 / max(abs(dx), 0.001),
                    CompanionGraphGeometry.nodeSize.height / 2 / max(abs(dy), 0.001))
                let start = CGPoint(x: source.x + dx * trim, y: source.y + dy * trim)
                let end = CGPoint(x: target.x - dx * trim, y: target.y - dy * trim)
                let bend = min(28, distance * 0.07)
                let control = CGPoint(x: (start.x + end.x) / 2 - dy / distance * bend,
                    y: (start.y + end.y) / 2 + dx / distance * bend)
                let emphasized = selectedID == edge.source || selectedID == edge.target
                let opacity: Double = emphasized ? 0.86 : selectedID == nil ? 0.33 : 0.10
                let color = graphColor(kinds[edge.source] ?? .context).opacity(opacity)
                var line = Path()
                line.move(to: start); line.addQuadCurve(to: end, control: control)
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: emphasized ? 2 : 1.2, lineCap: .round))
                let angle = atan2(end.y - control.y, end.x - control.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: end.x - cos(angle - 0.45) * 7, y: end.y - sin(angle - 0.45) * 7))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x - cos(angle + 0.45) * 7, y: end.y - sin(angle + 0.45) * 7))
                context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: emphasized ? 1.7 : 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
