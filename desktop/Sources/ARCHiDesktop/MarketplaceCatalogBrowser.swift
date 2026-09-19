import SwiftUI

@MainActor
struct MarketplaceCatalogBrowser: View {
    @ObservedObject var catalog: MarketplaceCatalogStore
    @State private var selectedID: String?

    private var selected: MarketplaceListing? { catalog.catalog.first { $0.id == selectedID } ?? catalog.catalog.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Shared designs").font(.system(size: 15, weight: .medium))
                Spacer()
                Text("\(catalog.catalogTotal) published").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                TextField("Find a design or creator", text: $catalog.search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await catalog.refreshCatalog() } }
                    .accessibilityIdentifier("marketplace.catalog.search")
                Button("Search", systemImage: "magnifyingglass") { Task { await catalog.refreshCatalog() } }
                    .disabled(catalog.isBusy).accessibilityIdentifier("marketplace.catalog.refresh")
            }
            if catalog.catalog.isEmpty {
                Text(catalog.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "No shared designs yet. Browse the included designs below, or create your own."
                     : "No designs found. Try another title or creator’s name.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    .accessibilityIdentifier("marketplace.catalog.empty")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                    ForEach(catalog.catalog) { listing in
                        Button { selectedID = listing.id } label: {
                            HStack(alignment: .center, spacing: 9) {
                                MarketplaceItemPreview(item: listing.recipe, size: 48)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(listing.recipe.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text("@\(listing.publisher.handle)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).help("@\(listing.publisher.handle)")
                                    Text("Version \(listing.version)").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.accent)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(WorkspaceSurface(emphasis: selected?.id == listing.id))
                        }.buttonStyle(.plain).accessibilityIdentifier("marketplace.catalog.listing.\(listing.id)")
                    }
                }
                if let selected {
                    WorkspaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            MarketplaceCatalogMetadata(recipe: selected.recipe, publisher: selected.publisher,
                                provenance: selected.provenance, version: selected.version)
                            if catalog.inventory.contains(where: { $0.recipeID == selected.recipeID }) {
                                Label("In your account library", systemImage: "checkmark.circle")
                                    .font(.callout).foregroundStyle(WorkspaceTheme.accent)
                            } else {
                                Button("Add to account library", systemImage: "plus") { Task { await catalog.acquire(selected) } }
                                    .buttonStyle(WorkspaceActionStyle(prominent: true)).disabled(!catalog.canMutate)
                                    .accessibilityIdentifier("marketplace.catalog.acquire")
                                if catalog.account == nil { Text("Sign in to save this design to your account.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if catalog.hasMoreCatalog {
                    Button("Load more designs") { Task { await catalog.refreshCatalog(more: true) } }.disabled(catalog.isBusy)
                }
            }
        }
    }
}

@MainActor
struct MarketplaceAccountLibrary: View {
    @ObservedObject var catalog: MarketplaceCatalogStore
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account library").font(.title3)
                    Text("Designs saved to your account. Download one to review and add it on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if catalog.account != nil {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await catalog.refreshInventory() } }
                        .disabled(catalog.isBusy).accessibilityIdentifier("marketplace.library.refresh")
                }
            }
            if catalog.account == nil {
                Text("Sign in above to see your saved designs.").foregroundStyle(.secondary)
            } else if catalog.inventory.isEmpty {
                Text("Your account library is empty. Add a published design from Discover.")
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("marketplace.library.empty")
            } else {
                ForEach(catalog.inventory) { entry in
                    WorkspaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            MarketplaceCatalogMetadata(recipe: entry.recipe, publisher: entry.publisher,
                                provenance: entry.provenance, version: entry.version)
                            HStack {
                                if store.itemLibrary.contains(entry.recipe) {
                                    Label("Installed on this Mac", systemImage: "checkmark.circle")
                                        .font(.callout).foregroundStyle(WorkspaceTheme.accent)
                                } else {
                                    Button("Download & review", systemImage: "square.and.arrow.down") { Task { await catalog.download(entry) } }
                                        .buttonStyle(WorkspaceActionStyle(prominent: true)).disabled(catalog.isBusy)
                                        .accessibilityIdentifier("marketplace.library.download.\(entry.id)")
                                }
                                Spacer()
                                if let date = entry.acquiredDate {
                                    Text("Saved \(date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Saved date unavailable").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if catalog.hasMoreInventory {
                    Button("More saved designs") { Task { await catalog.refreshInventory(more: true) } }.disabled(catalog.isBusy)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("marketplace.account-library")
    }
}

struct MarketplaceCatalogMetadata: View {
    let recipe: CompanionItemPackage
    let publisher: MarketplaceAccount
    let provenance: MarketplaceProvenance
    let version: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                MarketplaceItemPreview(item: recipe, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title).font(.system(size: 16, weight: .medium))
                    Text("Published by @\(publisher.handle) · version \(version)").font(.caption).foregroundStyle(.secondary)
                    Text(recipe.summary).font(.callout)
                }
            }
            Text("Design credit: \(recipe.creator) · \(recipe.license.rawValue)").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Credit & recipe details") {
                VStack(alignment: .leading, spacing: 7) {
                    Text(provenance.attribution)
                    if !provenance.source.isEmpty { Text("Source: \(provenance.source)") }
                    Text("\(provenance.declaration.title). Rights are declared by the publisher. Publishing does not change Arena stats. Registration remains separate.")
                    Text(recipe.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }
    }
}
