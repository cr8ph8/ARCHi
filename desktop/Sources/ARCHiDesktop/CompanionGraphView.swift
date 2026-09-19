import SwiftUI

enum CompanionGraphLayout: String, CaseIterable, Identifiable {
    case constellation = "Constellation"
    case radial = "Radial"
    case flow = "Flow"
    var id: String { rawValue }
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
        case .constellation:
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

    @State private var selectedID: String?
    @State private var query = ""
    @State private var kindFilter: CompanionGraphKind?
    @State private var layout = CompanionGraphLayout.constellation
    @State private var showsList = false
    @State private var zoom: CGFloat = 1
    @State private var fitRevision = 0

    init(snapshot: CompanionGraphSnapshot, onOpen: @escaping (CompanionGraphTarget) -> Void,
         initialLayout: CompanionGraphLayout = .constellation, initialSelectionID: String? = nil) {
        self.snapshot = snapshot
        self.onOpen = onOpen
        _layout = State(initialValue: initialLayout)
        _selectedID = State(initialValue: initialSelectionID)
    }

    private var visibleNodes: [CompanionGraphNode] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.nodes.filter { node in
            (kindFilter == nil || node.kind == kindFilter) && (search.isEmpty ||
                ([node.title, node.subtitle, node.status, node.kind.title] + node.details.flatMap { [$0.label, $0.value] })
                    .contains { $0.localizedStandardContains(search) })
        }
    }

    private var visibleEdges: [CompanionGraphEdge] {
        let ids = Set(visibleNodes.map(\.id))
        return snapshot.edges.filter { ids.contains($0.source) && ids.contains($0.target) }
    }

    // Keep only an ID in view state: replacement/removal immediately changes the inspector.
    private var selectedNode: CompanionGraphNode? { visibleNodes.first { $0.id == selectedID } }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    filters
                    if viewport.size.width >= 930 {
                        let graphHeight = max(280, viewport.size.height - 260)
                        HStack(alignment: .top, spacing: 16) {
                            graphCard(height: graphHeight)
                            ScrollView { inspector }
                                .frame(width: 270, height: graphHeight + 78, alignment: .top)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .id(selectedID)
                                .accessibilityIdentifier("companion-graph.inspector-scroll")
                        }
                    } else {
                        graphCard(height: max(280, min(400, viewport.size.height * 0.57)))
                        inspector
                    }
                }
                .padding(20)
                .frame(maxWidth: 1500, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onChange(of: visibleNodes.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .transaction { $0.animation = nil }
        .accessibilityIdentifier("companion-graph.workspace")
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LOCAL CONNECTIONS").font(.system(size: 9, weight: .semibold)).tracking(2)
                    .foregroundStyle(Color.teal)
                Text("Activity map").font(.system(size: 25, weight: .medium, design: .rounded))
                Text("\(visibleNodes.count) of \(snapshot.nodes.count) nodes · \(visibleEdges.count) connections")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion-graph.counts")
            }
            Spacer(minLength: 8)
            Button { showsList.toggle() } label: {
                Label(showsList ? "Graph" : "List", systemImage: showsList ? "point.3.connected.trianglepath.dotted" : "list.bullet")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel(showsList ? "Show graph" : "Show accessible node list")
            .accessibilityIdentifier("companion-graph.list-toggle")
        }
    }

    private var filters: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a node", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("Find a graph node").accessibilityIdentifier("companion-graph.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear graph search")
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            Picker("Node type", selection: $kindFilter) {
                Text("All types").tag(CompanionGraphKind?.none)
                ForEach(CompanionGraphKind.allCases) { kind in
                    Text("\(kind.title) · \(snapshot.nodes.filter { $0.kind == kind }.count)")
                        .tag(Optional(kind))
                }
            }
            .labelsHidden().frame(width: 160)
            .accessibilityLabel("Filter graph by node type").accessibilityIdentifier("companion-graph.type-filter")
        }.font(.system(size: 12))
    }

    private func graphCard(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Graph layout", selection: $layout) {
                    ForEach(CompanionGraphLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 320)
                .disabled(showsList).accessibilityIdentifier("companion-graph.layout")
                Spacer(minLength: 0)
                if !showsList {
                    Button { zoom = max(0.005, zoom - 0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                        .disabled(zoom <= 0.005).accessibilityLabel("Zoom out")
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 34)
                    Button { zoom = min(1.8, zoom + 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
                        .disabled(zoom >= 1.8).accessibilityLabel("Zoom in")
                    Button("Fit") { fitRevision += 1 }
                        .accessibilityLabel("Fit and center graph").accessibilityIdentifier("companion-graph.fit")
                }
            }
            .controlSize(.small).buttonStyle(.borderless).padding(12)
            Divider().opacity(0.6)
            Group {
                if visibleNodes.isEmpty {
                    emptyGraph
                } else if showsList {
                    nodeList
                } else {
                    graphSurface
                }
            }.frame(height: height)
            Divider().opacity(0.6)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                Text(showsList ? "Select a node to inspect its current record." : layoutHint)
                Spacer(minLength: 0)
                if snapshot.truncatedCount > 0 {
                    Text("\(snapshot.truncatedCount) records outside this snapshot")
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08), lineWidth: 1))
    }

    private var layoutHint: String {
        switch layout {
        case .constellation: "Grouped by type. Select a node; scroll or zoom to explore."
        case .radial: "Rings follow recorded links from the companion; unlinked nodes sit outside."
        case .flow: "Columns group record types. Arrows show recorded direction."
        }
    }

    private var graphSurface: some View {
        let nodes = visibleNodes
        let edges = visibleEdges
        let geometry = CompanionGraphGeometry.make(nodes: nodes, edges: edges, layout: layout)
        return GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        GraphConnections(nodes: nodes, edges: edges, geometry: geometry, selectedID: selectedID)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        ForEach(nodes) { node in
                            if let position = geometry.positions[node.id] {
                                GraphNodeButton(node: node, selected: selectedID == node.id) { selectedID = node.id }
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
                    Button { selectedID = node.id } label: {
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
            Text(snapshot.nodes.isEmpty ? "Connections will appear here" : "No matching nodes")
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
                    Button { selectedID = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Clear selected node")
                }
                if !node.subtitle.isEmpty && !subtitleIsReference {
                    Text(node.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !node.status.isEmpty {
                    Label(node.status, systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(graphColor(node.kind)).padding(.vertical, 4)
                }
                if let target = node.target {
                    Button(openTitle(target), systemImage: "arrow.up.right") { onOpen(target) }
                        .buttonStyle(.bordered).controlSize(.small).padding(.vertical, 5)
                        .accessibilityIdentifier("companion-graph.open-target")
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
                Label("Inspect a connection", systemImage: "scope")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(WorkspaceTheme.accent)
                Text("Select a node to see its source, status and recorded relationships.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                Text("The graph reflects available records. Arrangement and distance do not measure importance or certainty.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion-graph.inspector")
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
        let priority = ["Your kept words", "Excerpt", "Outcome", "Scope", "Access scope", "Meaning", "Content", "Retention"]
        return details.enumerated().filter { !isReferenceDetail($0.element) }.sorted { left, right in
            let leftRank = priority.firstIndex(of: left.element.label) ?? priority.count
            let rightRank = priority.firstIndex(of: right.element.label) ?? priority.count
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
    }

    @ViewBuilder private func selectedConnections(_ node: CompanionGraphNode) -> some View {
        let relationships = snapshot.edges.filter { $0.source == node.id || $0.target == node.id }
        if !relationships.isEmpty {
            Divider().padding(.vertical, 5)
            Text("RECORDED LINKS · \(relationships.count)")
                .font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
            ForEach(relationships.prefix(12)) { edge in
                let otherID = edge.source == node.id ? edge.target : edge.source
                if let other = snapshot.nodes.first(where: { $0.id == otherID }) {
                    Button {
                        query = ""
                        kindFilter = nil
                        selectedID = other.id
                    } label: {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: edge.source == node.id ? "arrow.up.right" : "arrow.down.left")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.title).fontWeight(.medium)
                                Text(edge.label).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 11)).padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(graphColor(other.kind))
                }
            }
            if relationships.count > 12 {
                Text("\(relationships.count - 12) more recorded links in the graph")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func openTitle(_ target: CompanionGraphTarget) -> String {
        switch target {
        case .assistant: "Open assistant"
        case .context: "Open shared context"
        case .memory: "Open memory"
        case .advanced: "Open local receipts"
        case .capabilities: "Open ARC"
        case .interactiveARC: "Open ARC3 episode"
        case .arcEvidence: "Open this ARC receipt"
        case .steward: "Open Usage"
        case .stewardTask: "Open this run in Usage"
        }
    }
}

private func graphColor(_ kind: CompanionGraphKind) -> Color {
    switch kind {
    case .companion: Color.teal
    case .source: Color.blue
    case .lesson: WorkspaceTheme.accent
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
