import SwiftUI

@MainActor
struct MarketplacePublishingView: View {
    @ObservedObject var catalog: MarketplaceCatalogStore

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(catalog.editingListing == nil ? "Share your design" : "Update your listing")
                    .font(.system(size: 16, weight: .medium))
                if let listing = catalog.editingListing {
                    Text(listing.visibilitySummary).font(.caption).foregroundStyle(WorkspaceTheme.accent)
                        .accessibilityIdentifier("marketplace.creator.version")
                }
                if let account = catalog.account {
                    Text("Sharing as @\(account.handle)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sign in to share this design. You can add it on this Mac or export it without an account.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Picker("Design origin", selection: $catalog.provenance.declaration) {
                    ForEach(MarketplaceProvenance.Declaration.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("marketplace.creator.origin")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Design credit (required)").font(.caption)
                    TextField("Credit for this design", text: $catalog.provenance.attribution, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .help("Credit the people who made this design, using up to 500 characters.")
                        .accessibilityIdentifier("marketplace.creator.attribution")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(catalog.provenance.declaration == .adaptation ? "Original source (required)" : "Source (optional)").font(.caption)
                    TextField("Original source and license reference", text: $catalog.provenance.source, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .help("Include the original source and license when adapting another design. Up to 500 characters.")
                        .accessibilityIdentifier("marketplace.creator.source")
                }
                Toggle("I have permission to distribute this design under \(catalog.draft.license.rawValue).",
                       isOn: $catalog.provenance.rightsConfirmed)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("marketplace.creator.rights")
                Button(catalog.editingListing == nil ? "Save draft" : "Save draft changes", systemImage: "square.and.arrow.up") {
                    Task { await catalog.saveDraft() }
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true)).disabled(!catalog.canSaveDraft)
                .accessibilityIdentifier("marketplace.creator.save-draft")
                Text("Your draft stays in your account until you publish it from My listings. An earlier published version stays available while you edit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(catalog.isBusy || catalog.hasPendingMutation)
        }
    }
}

@MainActor
struct MarketplaceCreatorListings: View {
    @ObservedObject var catalog: MarketplaceCatalogStore
    @State private var publishing: MarketplaceListing?
    @State private var archiving: MarketplaceListing?
    @State private var showsListings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Design studio").font(.title3)
                Spacer()
                Button("New design", systemImage: "plus") { catalog.startNewDraft() }
                    .disabled(catalog.isBusy || catalog.hasPendingMutation)
                    .accessibilityIdentifier("marketplace.creator.new")
                if catalog.account != nil {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await catalog.refreshListings() } }
                        .disabled(catalog.isBusy).accessibilityIdentifier("marketplace.creator.refresh")
                }
            }
            if catalog.account != nil {
                DisclosureGroup("My listings · \(catalog.listingsTotal)", isExpanded: $showsListings) {
                    VStack(alignment: .leading, spacing: 10) {
                        if catalog.listings.isEmpty {
                            Text("Create a design below, then save a draft to share it.").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(catalog.listings) { listing in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(listing.recipe.title).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(listing.visibilitySummary).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 13) {
                                    Button("Edit") { catalog.edit(listing) }
                                        .accessibilityIdentifier("marketplace.creator.edit.\(listing.id)")
                                    if listing.status == .draft {
                                        Button("Publish") { publishing = listing }
                                            .accessibilityIdentifier("marketplace.creator.publish.\(listing.id)")
                                    }
                                    if listing.status != .archived {
                                        Button("Archive") { archiving = listing }
                                            .accessibilityIdentifier("marketplace.creator.archive.\(listing.id)")
                                    }
                                    Button("Version history") { Task { await catalog.loadHistory(listing) } }
                                        .accessibilityIdentifier("marketplace.creator.history.\(listing.id)")
                                }.disabled(!catalog.canMutate)
                                if catalog.historyListingID == listing.id {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(catalog.history, id: \.version) { version in
                                            Text("Version \(version.version) · \(version.status.rawValue) · \(version.recipe.title) · design revision \(version.recipe.revision)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        if catalog.hasMoreHistory {
                                            Button("More versions") { Task { await catalog.loadHistory(listing, more: true) } }
                                                .disabled(catalog.isBusy)
                                        }
                                    }.padding(.top, 4).accessibilityElement(children: .contain).accessibilityIdentifier("marketplace.creator.history")
                                }
                            }.padding(12).modifier(WorkspaceSurface(emphasis: catalog.editingListing?.id == listing.id))
                        }
                        if catalog.hasMoreListings {
                            Button("More listings") { Task { await catalog.refreshListings(more: true) } }.disabled(catalog.isBusy)
                        }
                    }.padding(.top, 10)
                }.font(.callout)
            }
        }
        .confirmationDialog("Publish this design?", isPresented: Binding(
            get: { publishing != nil }, set: { if !$0 { publishing = nil } }), titleVisibility: .visible) {
                if let listing = publishing {
                    Button("Publish \(listing.recipe.title)") {
                        publishing = nil
                        Task { await catalog.publish(listing) }
                    }
                }
                Button("Cancel", role: .cancel) { publishing = nil }
        } message: {
            Text("This version will appear in the local catalog for accounts on this Mac. Your credit and license will appear with the design.")
        }
        .confirmationDialog("Archive this listing?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
                if let listing = archiving {
                    Button("Archive \(listing.recipe.title)", role: .destructive) {
                        archiving = nil
                        Task { await catalog.archive(listing) }
                    }
                }
                Button("Cancel", role: .cancel) { archiving = nil }
        } message: {
            Text("This design will leave the catalog. Anyone who already saved a version keeps it in their account library.")
        }
    }
}
