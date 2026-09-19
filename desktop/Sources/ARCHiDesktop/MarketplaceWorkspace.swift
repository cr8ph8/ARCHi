import SwiftUI

/// Creator catalog and local installation share one native design workspace.
@MainActor
struct MarketplaceWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var service: MarketplaceCatalogStore

    init(store: CompanionStore) {
        self.store = store
        service = store.marketplaceCatalog
    }
    private enum Page: String, CaseIterable, Identifiable {
        case discover = "Discover", collection = "On this Mac", accountLibrary = "Account library", create = "Create"
        var id: String { rawValue }
    }
    @State private var page: Page = .discover
    @State private var query = ""
    @State private var selected: CompanionItemPackage? = CompanionItemCatalog.designs.first
    @State private var removal: CompanionItemPackage?
    @State private var reviewOriginIsCatalog = false
    private enum ImportHandoff {
        case variation(CompanionItemPackage), workTogether(CompanionItemPackage)
    }
    @State private var importHandoff: ImportHandoff?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    MarketplaceCompanionCard(store: store)
                    MarketplaceConnectionBar(catalog: service)
                    Picker("Marketplace section", selection: $page) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .accessibilityIdentifier("marketplace.sections")
                    if page == .accountLibrary {
                        MarketplaceAccountLibrary(catalog: service, store: store)
                    } else if page == .create {
                        MarketplaceCreatorListings(catalog: service)
                        if geometry.size.width >= 1000 {
                            HStack(alignment: .top, spacing: 18) {
                                MarketplaceCreatorForm(draft: $service.draft).disabled(service.isBusy || service.hasPendingMutation).frame(maxWidth: .infinity)
                                creatorReview.frame(width: 380)
                            }
                        } else {
                            MarketplaceCreatorForm(draft: $service.draft).disabled(service.isBusy || service.hasPendingMutation)
                            creatorReview
                        }
                    } else {
                        if page == .discover, service.connected {
                            MarketplaceCatalogBrowser(catalog: service)
                            Divider().padding(.vertical, 4)
                        }
                        browseToolbar
                        if geometry.size.width >= 1000 {
                            HStack(alignment: .top, spacing: 18) {
                                catalog.frame(maxWidth: .infinity)
                                if let visibleSelection {
                                    detail(visibleSelection).frame(width: 380)
                                }
                            }
                        } else {
                            catalog
                            if let visibleSelection { detail(visibleSelection) }
                        }
                    }
                    Label(store.marketplaceMessage, systemImage: "internaldrive")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("marketplace.status")
                    if service.connected {
                        Text(service.message).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("marketplace.catalog.status")
                    }
                    rules
                }
                .padding(geometry.size.width < 800 ? 20 : 28)
                .frame(maxWidth: 1190, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marketplace.workspace")
        .onChange(of: page) { _, _ in
            query = ""
            selected = nil
        }
        .onChange(of: service.downloadedRecipe, initial: true) { _, recipe in
            guard let recipe else { return }
            reviewOriginIsCatalog = true
            store.importedMarketItem = recipe
            service.downloadedRecipe = nil
        }
        .sheet(item: $store.importedMarketItem, onDismiss: completeImportHandoff) { item in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(reviewOriginIsCatalog ? "Review downloaded recipe" : "Review imported recipe").font(.title2)
                    Text("Review this design before adding it to your collection.")
                        .foregroundStyle(.secondary)
                    detail(item, allowsRemoval: false)
                    Text(store.marketplaceMessage).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("marketplace.import.status")
                    Button("Done") { store.importedMarketItem = nil }.keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("marketplace.import.done")
                }.padding(24)
            }.frame(width: 560, height: 570)
        }
        .confirmationDialog("Remove this design from this Mac?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            if let removal {
                Button("Remove \(removal.title)", role: .destructive) {
                    if store.removeMarketItem(removal), selected?.id == removal.id { selected = nil }
                    self.removal = nil
                }
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: {
            Text("Also removes this item from your current and saved outfit. Shared recipe files stay where you exported them.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                WorkspaceEyebrow(text: "Marketplace")
                Text("Designs for your companion.").font(.system(size: 24, weight: .medium))
            }
            Spacer(minLength: 0)
            Image(systemName: "bag")
                .font(.system(size: 27, weight: .ultraLight)).foregroundStyle(WorkspaceTheme.accent)
                .padding(.top, 5).accessibilityHidden(true)
        }
    }

    private var filteredItems: [CompanionItemPackage] {
        let items = page == .collection ? store.itemLibrary : CompanionItemCatalog.designs
        let needle = showsLocalSearch ? query.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return needle.isEmpty ? items : items.filter { ($0.title + " " + $0.creator).localizedCaseInsensitiveContains(needle) }
    }

    /// Search and library changes can remove a selected recipe from the visible
    /// list. Never show actions for a hidden result, and select the first item
    /// when a previously empty collection receives its first local recipe.
    private var visibleSelection: CompanionItemPackage? {
        filteredItems.first { $0.id == selected?.id } ?? filteredItems.first
    }

    private var showsLocalSearch: Bool { page != .discover || !service.connected }

    private var browseToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if showsLocalSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a design or creator", text: $query)
                            .textFieldStyle(.plain).accessibilityIdentifier("marketplace.search")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("Clear design search")
                                .accessibilityIdentifier("marketplace.search.clear")
                        }
                    }
                    .padding(10).modifier(WorkspaceSurface())
                } else {
                    Text("Included designs").font(.system(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                }
                Button("Import recipe", systemImage: "square.and.arrow.down") {
                    reviewOriginIsCatalog = false
                    store.importMarketItem()
                }
                    .buttonStyle(WorkspaceActionStyle())
                    .accessibilityIdentifier("marketplace.import")
            }
            if showsLocalSearch {
                HStack {
                    Text(page == .collection ? "Installed on this Mac" : "Included designs")
                        .font(.system(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                    Text(page == .collection
                         ? "\(store.itemLibrary.count) / \(CompanionItemPackage.maximumLibraryCount) saved here"
                         : "\(filteredItems.count) \(filteredItems.count == 1 ? "design" : "designs")")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            if filteredItems.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(filteredItems) { item in
                        Button { selected = item } label: { tile(item) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview \(item.title), \(CompanionItemCatalog.registeredDesign(for: item).label)")
                            .accessibilityAddTraits(visibleSelection?.id == item.id ? .isSelected : [])
                            .accessibilityIdentifier("marketplace.design.\(item.id.prefix(12))")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: query.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                    .font(.system(size: 27, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                Text(query.isEmpty ? "Room for your first item." : "No matching designs.")
                    .font(.system(size: 18, weight: .medium))
                Text(query.isEmpty
                     ? "Add a design from Discover or create a staff of your own. Your recipes stay on this Mac."
                     : "Try an item name or creator. Clear your search to see the whole collection.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    if query.isEmpty {
                        Button("Explore designs") { page = .discover }
                            .buttonStyle(WorkspaceActionStyle(prominent: true))
                        Button("Create a design") { page = .create }
                            .buttonStyle(WorkspaceActionStyle())
                    } else {
                        Button("Clear search") { query = "" }
                            .buttonStyle(WorkspaceActionStyle())
                    }
                }
            }
            .padding(.vertical, 10)
            .accessibilityIdentifier("marketplace.empty-state")
        }
    }

    private func tile(_ item: CompanionItemPackage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            MarketplaceItemPreview(item: item, size: 72)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background {
                    RadialGradient(colors: [WorkspaceTheme.accent.opacity(0.10), .clear],
                        center: .center, startRadius: 12, endRadius: 96)
                }
            Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
            Text(item.creator).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Divider().overlay(WorkspaceTheme.line)
            Label(item.action == .decoration ? "Wearable" : "Point to a passage",
                  systemImage: item.action == .decoration ? "sparkles" : "text.cursor")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if store.preferences.equipment.design?.id == item.id {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Wearing now")
                } else { Text(store.itemLibrary.contains(item) ? "On this Mac" : "Included design") }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(WorkspaceSurface(emphasis: visibleSelection?.id == item.id))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WorkspaceTheme.accent.opacity(visibleSelection?.id == item.id ? 0.65 : 0), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detail(_ item: CompanionItemPackage, allowsRemoval: Bool = true) -> some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    MarketplaceItemPreview(item: item, size: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.title3.weight(.semibold))
                            .accessibilityIdentifier("marketplace.detail.title")
                        Text(item.creator).font(.caption).foregroundStyle(.secondary)
                        Text(CompanionItemCatalog.registeredDesign(for: item).isRegistered ? "Included design" : "Creator design").font(.caption.weight(.semibold)).foregroundStyle(WorkspaceTheme.accent)
                        Text(item.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(item.action == .pointSelection
                     ? "Point to a passage in Work together."
                     : "A decorative wearable for your companion.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Arena stats stay unchanged.").font(.caption).foregroundStyle(.secondary)
                if collectionIsFull(for: item) {
                    Text("Your collection is full. Remove a design from On this Mac before adding this one. You can still edit or export this recipe.")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("marketplace.collection-full")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { actions(item, allowsRemoval: allowsRemoval) }
                    VStack(alignment: .leading) { actions(item, allowsRemoval: allowsRemoval) }
                }
                if store.canUseMarketItemInWorkTogether(item) {
                    Button("Use in Work together", systemImage: "text.cursor") { handoff(.workTogether(item)) }
                        .accessibilityHint("Opens your working copy. Select a passage there to point to it.")
                        .accessibilityIdentifier("marketplace.use-work-together")
                }
                DisclosureGroup("Recipe details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Design revision \(item.revision)").font(.caption)
                        Text(CompanionItemCatalog.registeredDesign(for: item).label).font(.caption.weight(.medium))
                        Text("Recipe license: \(item.license.rawValue)").font(.caption)
                        if item.action == .pointSelection {
                            Text("\(item.defaultGesture.summary) Your saved gesture takes precedence.").font(.caption)
                        }
                        Text("The recipe uses supported local choices. Creator and license are declarations; this check does not verify them.")
                            .font(.caption).accessibilityIdentifier("marketplace.recipe-review")
                        if !CompanionItemCatalog.registeredDesign(for: item).isRegistered {
                            Text("This variation can be added locally. It does not exactly match a bundled registered design.")
                                .font(.caption).accessibilityIdentifier("marketplace.registration-explanation")
                        }
                        Text(item.id)
                            .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 7)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func actions(_ item: CompanionItemPackage, allowsRemoval: Bool) -> some View {
        if store.itemLibrary.contains(item) {
            Button(store.preferences.equipment.design?.id == item.id ? "Equipped · Unequip" : "Equip") {
                if store.preferences.equipment.design?.id == item.id { _ = store.unequipMarketItem(item) }
                else { _ = store.equipMarketItem(item) }
            }.buttonStyle(WorkspaceActionStyle(prominent: true)).accessibilityIdentifier("marketplace.equip")
            if allowsRemoval {
                Button("Remove", role: .destructive) { removal = item }
                    .accessibilityIdentifier("marketplace.remove")
            }
        } else {
            Button("Add on this Mac", systemImage: "plus") { _ = store.collectMarketItem(item) }
                .buttonStyle(WorkspaceActionStyle(prominent: true)).disabled(!item.isValid || collectionIsFull(for: item))
                .accessibilityIdentifier("marketplace.collect")
        }
        Button("Export recipe") { store.exportMarketItem(item) }.disabled(!item.isValid)
            .accessibilityIdentifier("marketplace.export")
        Button("Make a variation") { handoff(.variation(item)) }
            .accessibilityIdentifier("marketplace.variation")
    }

    private func collectionIsFull(for item: CompanionItemPackage) -> Bool {
        !store.itemLibrary.contains(item) && store.itemLibrary.count >= CompanionItemPackage.maximumLibraryCount
    }

    /// Finish dismissing review before revealing the destination. In particular,
    /// changing the draft must not leave Create hidden behind the import sheet.
    private func handoff(_ action: ImportHandoff) {
        if store.importedMarketItem != nil {
            importHandoff = action
            store.importedMarketItem = nil
        } else { perform(action) }
    }

    private func completeImportHandoff() {
        reviewOriginIsCatalog = false
        guard let action = importHandoff else { return }
        importHandoff = nil
        perform(action)
    }

    private func perform(_ action: ImportHandoff) {
        switch action {
        case .variation(let item):
            service.makeVariation(item)
            page = .create
        case .workTogether(let item):
            _ = store.useMarketItemInWorkTogether(item)
        }
    }

    private var creatorReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceEyebrow(text: "Review your design")
            if service.draft.isValid { detail(service.draft) }
            else {
                WorkspaceCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("A few details to finish").font(.headline)
                        ForEach(service.draft.review.issues) { check in
                            Label(check.message, systemImage: "exclamationmark.circle")
                                .accessibilityIdentifier("marketplace.create.review.\(check.field.rawValue)")
                        }
                    }
                    .foregroundStyle(.red).font(.callout)
                }
            }
            MarketplacePublishingView(catalog: service)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Your collection").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                Text("Free recipe access").font(.system(size: 10))
            }
            Text("Add a design to this Mac, then Equip it. Save choices keeps your outfit for next time.")
                .font(.system(size: 11))
            DisclosureGroup("About designs & sharing") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your account library keeps saved designs in the local catalog. Download and review a design before adding it to this Mac.")
                    Text("Registered means every field matches the approved local Alpha catalog. Creator names and licenses remain declarations. No Arena effects are approved in this release.")
                    Text("A recipe fingerprint identifies content. It does not establish ownership, scarcity, or an issued edition. Export includes the design, never your private memory or companion identity.")
                    Link("Open-source foundation", destination: URL(string: "https://github.com/cr8ph8/ARCHi")!)
                }.font(.system(size: 11)).padding(.top, 7)
            }
            .font(.system(size: 11))
        }.foregroundStyle(.secondary)
    }
}
