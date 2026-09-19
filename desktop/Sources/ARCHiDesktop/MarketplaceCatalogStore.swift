import Foundation
import Combine

/// Account/catalog state lives for this app session. Companion identity, memory,
/// saved equipment and the bounded installed collection remain in CompanionStore.
/// Initialization and navigation perform no network or persistence operations.
@MainActor
final class MarketplaceCatalogStore: ObservableObject {
    @Published var endpointText = MarketplaceCatalogClient.defaultEndpoint
    @Published var search = ""
    @Published var draft = CompanionItemPackage.creatorDefault
    @Published var provenance = MarketplaceProvenance()
    @Published private(set) var connected = false
    @Published private(set) var account: MarketplaceAccount?
    @Published private(set) var catalog: [MarketplaceListing] = []
    @Published private(set) var inventory: [MarketplaceInventoryEntry] = []
    @Published private(set) var listings: [MarketplaceListing] = []
    @Published private(set) var history: [MarketplaceListing] = []
    @Published private(set) var historyListingID: String?
    @Published private(set) var editingListing: MarketplaceListing?
    @Published private(set) var catalogTotal = 0
    @Published private(set) var inventoryTotal = 0
    @Published private(set) var listingsTotal = 0
    @Published private(set) var historyTotal = 0
    @Published private(set) var isBusy = false
    @Published private(set) var message = "Connect to a development catalog to discover and publish creator recipes."
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasPendingMutation = false
    @Published var downloadedRecipe: CompanionItemPackage?

    private let transport: any MarketplaceHTTPTransport
    private var client: MarketplaceCatalogClient
    private var token: String?
    private var catalogOffset = 0, inventoryOffset = 0, listingsOffset = 0, historyOffset = 0
    private var searchedQuery = ""
    private struct PendingMutation {
        enum Kind { case draft, visibility, acquisition }
        let request: URLRequest
        let kind: Kind
    }
    private var pending: PendingMutation?

    init(transport: any MarketplaceHTTPTransport = MarketplaceURLTransport()) {
        self.transport = transport
        client = try! MarketplaceCatalogClient(transport: transport)
    }

    var canMutate: Bool { connected && account != nil && !isBusy && !hasPendingMutation }
    var canSaveDraft: Bool { canMutate && draft.isValid && provenance.isValid }
    var hasMoreCatalog: Bool { catalogOffset < catalogTotal && catalogOffset <= 10_000 }
    var hasMoreInventory: Bool { inventoryOffset < inventoryTotal && inventoryOffset <= 10_000 }
    var hasMoreListings: Bool { listingsOffset < listingsTotal && listingsOffset <= 10_000 }
    var hasMoreHistory: Bool { historyOffset < historyTotal && historyOffset <= 10_000 }

    func connect() async {
        guard account == nil, !hasPendingMutation else { return }
        await run {
            let candidate = try MarketplaceCatalogClient(endpoint: self.endpointText, transport: self.transport)
            let health = try await candidate.value(MarketplaceHealth.self, request: candidate.request(path: "health"))
            guard health.isSupported else { throw MarketplaceServiceError(code: "unsupported_service", status: nil) }
            self.client = candidate
            self.connected = true
            try await self.loadCatalog(reset: true)
            self.message = "Development catalog connected. Published recipes are visible in this service."
        }
    }

    func createAccount(handle: String, displayName: String, password: String) async -> Bool {
        guard connected else { return false }
        var succeeded = false
        await run {
            struct Body: Encodable { let handle: String; let displayName: String; let password: String }
            let response = try await self.client.value(MarketplaceAccountResponse.self,
                request: self.client.request(path: "accounts", method: "POST", body: MarketplaceCatalogClient.encode(
                    Body(handle: handle, displayName: displayName, password: password))))
            guard response.account.isValid else { throw MarketplaceServiceError(code: "invalid_response", status: nil) }
            self.message = "Account created. Sign in to publish and build your account library."
            succeeded = true
        }
        return succeeded
    }

    func signIn(handle: String, password: String) async {
        guard connected, account == nil, !hasPendingMutation else { return }
        await run {
            struct Body: Encodable { let handle: String; let password: String }
            let session = try await self.client.value(MarketplaceSession.self,
                request: self.client.request(path: "sessions", method: "POST", body: MarketplaceCatalogClient.encode(Body(handle: handle, password: password))))
            guard session.account.isValid, !session.token.isEmpty, session.token.utf8.count <= 512,
                  session.token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
                throw MarketplaceServiceError(code: "invalid_response", status: nil)
            }
            self.token = session.token
            self.account = session.account
            self.message = "Signed in as @\(session.account.handle). This session stays in memory until you quit or sign out."
            try await self.loadInventory(reset: true)
            try await self.loadListings(reset: true)
        }
    }

    func signOut() async {
        guard let token, !hasPendingMutation else { return }
        await run {
            let response = try await self.client.value(MarketplaceSignOutResponse.self,
                request: self.client.request(path: "sessions/current", method: "DELETE", token: token))
            guard response.signedOut else { throw MarketplaceServiceError(code: "invalid_response", status: nil) }
            self.forgetSession()
            self.message = "Signed out. Items installed on this Mac remain available."
        }
    }

    func refreshCatalog(more: Bool = false) async {
        guard connected, !more || hasMoreCatalog else { return }
        await run { try await self.loadCatalog(reset: !more) }
    }
    func refreshInventory(more: Bool = false) async {
        guard account != nil, !more || hasMoreInventory else { return }
        await run { try await self.loadInventory(reset: !more) }
    }
    func refreshListings(more: Bool = false) async {
        guard account != nil, !more || hasMoreListings else { return }
        await run { try await self.loadListings(reset: !more) }
    }

    func startNewDraft() {
        guard !isBusy, !hasPendingMutation else { return }
        editingListing = nil
        draft = .creatorDefault
        provenance = .init()
    }
    func makeVariation(_ recipe: CompanionItemPackage) {
        guard !isBusy, !hasPendingMutation else { return }
        editingListing = nil
        draft = recipe
        draft.creator = "Local creator"
        provenance = .init(declaration: .adaptation)
    }
    func edit(_ listing: MarketplaceListing) {
        guard !isBusy, !hasPendingMutation, listing.publisher.id == account?.id else { return }
        editingListing = listing
        draft = listing.recipe
        provenance = listing.provenance
    }

    func saveDraft() async {
        guard canSaveDraft, let token else { return }
        await run {
            struct Body: Encodable { let recipe: CompanionItemPackage; let provenance: MarketplaceProvenance; let expectedVersion: Int? }
            let prior = self.editingListing
            let body = try MarketplaceCatalogClient.encode(Body(recipe: self.draft, provenance: self.provenance, expectedVersion: prior?.version))
            self.retain(self.client.request(path: prior.map { "listings/\($0.id)" } ?? "listings",
                method: prior == nil ? "POST" : "PUT", token: token, body: body, key: UUID().uuidString), kind: .draft)
            try await self.executePending()
        }
    }

    func publish(_ listing: MarketplaceListing) async { await changeVisibility(listing, action: "publish") }
    func archive(_ listing: MarketplaceListing) async { await changeVisibility(listing, action: "archive") }
    private func changeVisibility(_ listing: MarketplaceListing, action: String) async {
        guard canMutate, let token, listing.publisher.id == account?.id else { return }
        await run {
            struct Body: Encodable { let expectedVersion: Int }
            let body = try MarketplaceCatalogClient.encode(Body(expectedVersion: listing.version))
            self.retain(self.client.request(path: "listings/\(listing.id)/\(action)", method: "POST", token: token,
                body: body, key: UUID().uuidString), kind: .visibility)
            try await self.executePending()
        }
    }

    func acquire(_ listing: MarketplaceListing) async {
        guard canMutate, let token, listing.status == .published else { return }
        await run {
            struct Body: Encodable { let listingID: String; let version: Int; let recipeID: String }
            let body = try MarketplaceCatalogClient.encode(Body(listingID: listing.id, version: listing.version, recipeID: listing.recipeID))
            self.retain(self.client.request(path: "inventory", method: "POST", token: token, body: body, key: UUID().uuidString), kind: .acquisition)
            try await self.executePending()
        }
    }

    func download(_ entry: MarketplaceInventoryEntry) async {
        guard account != nil else { return }
        await run {
            self.downloadedRecipe = try await self.client.download(listingID: entry.listingID, version: entry.version,
                recipeID: entry.recipeID, token: self.token)
            self.message = "Downloaded and checked \(entry.recipe.title). Review it before adding it on this Mac."
        }
    }

    func loadHistory(_ listing: MarketplaceListing, more: Bool = false) async {
        guard account?.id == listing.publisher.id, !more || hasMoreHistory else { return }
        await run {
            let reset = !more || self.historyListingID != listing.id
            let response = try await self.client.value(MarketplacePage<MarketplaceListing>.self,
                request: self.client.request(path: "listings/\(listing.id)/versions", token: self.token,
                    query: self.pagination(reset ? 0 : self.historyOffset)))
            guard response.isValid, response.items.allSatisfy({ $0.isValid && $0.id == listing.id }) else {
                throw MarketplaceServiceError(code: "invalid_response", status: nil)
            }
            self.historyListingID = listing.id
            self.history = reset ? response.items : self.history + response.items
            self.historyTotal = response.total
            self.historyOffset = response.offset + response.items.count
        }
    }

    func retryPending() async {
        guard pending != nil else { return }
        await run { try await self.executePending() }
    }

    private func retain(_ request: URLRequest, kind: PendingMutation.Kind) {
        pending = .init(request: request, kind: kind)
        hasPendingMutation = true
    }
    private func executePending() async throws {
        guard let pending else { return }
        do {
            switch pending.kind {
            case .draft, .visibility:
                let response = try await client.value(MarketplaceListingResponse.self, request: pending.request)
                guard response.listing.isValid, response.listing.publisher.id == account?.id else {
                    throw MarketplaceServiceError(code: "invalid_response", status: nil)
                }
                let listing = response.listing
                if case .draft = pending.kind {
                    editingListing = listing
                    draft = listing.recipe
                    provenance = listing.provenance
                } else if editingListing?.id == listing.id {
                    editingListing = listing
                }
                listings.removeAll { $0.id == listing.id }
                listings.insert(listing, at: 0)
                message = "\(listing.recipe.title): \(listing.visibilitySummary.lowercased())."
            case .acquisition:
                let response = try await client.value(MarketplaceAcquisitionResponse.self, request: pending.request)
                guard response.entry.isValid else { throw MarketplaceServiceError(code: "invalid_response", status: nil) }
                inventory.removeAll { $0.recipeID == response.entry.recipeID }
                inventory.insert(response.entry, at: 0)
                message = "\(response.entry.recipe.title) is in your account library. Download and review to install it on this Mac."
            }
        } catch {
            // Only the response to this retained mutation can close its recovery
            // record. Unrelated reads and service/transport failures cannot.
            if let service = error as? MarketplaceServiceError, let status = service.status,
               (400...499).contains(status) {
                self.pending = nil
                hasPendingMutation = false
            }
            throw error
        }
        self.pending = nil
        hasPendingMutation = false
        // The mutation receipt is already confirmed. A refresh failure must not
        // retry the mutation or turn that committed receipt into an unknown result.
        do {
            try await loadCatalog(reset: true)
            try await loadListings(reset: true)
            try await loadInventory(reset: true)
        } catch {
            if let service = error as? MarketplaceServiceError, service.status == 401 {
                forgetSession()
                errorMessage = "Saved in the service. Your session ended; sign in again to reload the lists."
            } else { errorMessage = "Saved in the service; refreshing the lists failed. Use Refresh to reload them." }
        }
    }

    private func pagination(_ offset: Int) -> [URLQueryItem] {
        [.init(name: "limit", value: "40"), .init(name: "offset", value: String(offset))]
    }
    private func loadCatalog(reset: Bool) async throws {
        let query = reset ? search : searchedQuery
        guard query.utf16.count <= 100 else { throw MarketplaceServiceError(code: "validation_failed", status: nil) }
        let response = try await client.value(MarketplacePage<MarketplaceListing>.self,
            request: client.request(path: "catalog", query: pagination(reset ? 0 : catalogOffset) + [.init(name: "q", value: query)]))
        guard response.isValid, response.items.allSatisfy({ $0.isValid && $0.status == .published }) else {
            throw MarketplaceServiceError(code: "invalid_response", status: nil)
        }
        catalog = reset ? response.items : catalog + response.items.filter { next in !catalog.contains { $0.id == next.id } }
        catalogTotal = response.total; catalogOffset = response.offset + response.items.count; searchedQuery = query
    }
    private func loadInventory(reset: Bool) async throws {
        let response = try await client.value(MarketplacePage<MarketplaceInventoryEntry>.self,
            request: client.request(path: "inventory", token: token, query: pagination(reset ? 0 : inventoryOffset)))
        guard response.isValid, response.items.allSatisfy(\.isValid) else { throw MarketplaceServiceError(code: "invalid_response", status: nil) }
        inventory = reset ? response.items : inventory + response.items.filter { next in !inventory.contains { $0.id == next.id } }
        inventoryTotal = response.total; inventoryOffset = response.offset + response.items.count
    }
    private func loadListings(reset: Bool) async throws {
        let response = try await client.value(MarketplacePage<MarketplaceListing>.self,
            request: client.request(path: "me/listings", token: token, query: pagination(reset ? 0 : listingsOffset)))
        guard response.isValid, response.items.allSatisfy({ $0.isValid && $0.publisher.id == account?.id }) else {
            throw MarketplaceServiceError(code: "invalid_response", status: nil)
        }
        listings = reset ? response.items : listings + response.items.filter { next in !listings.contains { $0.id == next.id } }
        listingsTotal = response.total; listingsOffset = response.offset + response.items.count
    }
    private func run(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await action() }
        catch {
            if let service = error as? MarketplaceServiceError, service.status == 401 { forgetSession() }
            if hasPendingMutation {
                errorMessage = "The service response was interrupted. It may have saved the change. Retry the same request to confirm its result."
            } else if error is URLError {
                errorMessage = "Cannot reach the development catalog. Check that it is running, then try again."
            } else { errorMessage = error.localizedDescription }
        }
    }
    private func forgetSession() {
        token = nil; account = nil; inventory = []; listings = []; history = []
        inventoryTotal = 0; listingsTotal = 0; historyTotal = 0
        inventoryOffset = 0; listingsOffset = 0; historyOffset = 0
        editingListing = nil; historyListingID = nil; downloadedRecipe = nil
        provenance.rightsConfirmed = false
    }
}
