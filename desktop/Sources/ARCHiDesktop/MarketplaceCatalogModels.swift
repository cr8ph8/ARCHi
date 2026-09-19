import Foundation

struct MarketplaceAccount: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let createdAt: String

    var isValid: Bool {
        UUID(uuidString: id) != nil && handle.range(of: "\\A[a-z][a-z0-9_]{2,31}\\z", options: .regularExpression) != nil
            && MarketplaceProvenance.validText(displayName, maximum: 48, required: true)
    }
}

struct MarketplaceProvenance: Codable, Equatable, Sendable {
    enum Declaration: String, Codable, CaseIterable, Identifiable, Sendable {
        case original, adaptation = "licensed-adaptation"
        var id: String { rawValue }
        var title: String { self == .original ? "Original design" : "Licensed adaptation" }
    }
    var declaration: Declaration = .original
    var attribution = ""
    var source = ""
    var rightsConfirmed = false

    var isValid: Bool {
        rightsConfirmed && Self.validText(attribution, maximum: 500, required: true)
            && Self.validText(source, maximum: 500, required: declaration == .adaptation)
    }

    static func validText(_ value: String, maximum: Int, required: Bool) -> Bool {
        value.utf16.count <= maximum
            && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !value.unicodeScalars.contains {
                $0.value < 0x20 || (0x7f...0x9f).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029
            }
    }
}

struct MarketplaceListing: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable { case draft, published, archived }
    let id: String
    let version: Int
    let status: Status
    let publishedVersion: Int?
    let publisher: MarketplaceAccount
    let recipeID: String
    let recipe: CompanionItemPackage
    let provenance: MarketplaceProvenance
    let createdAt: String
    let updatedAt: String

    var isValid: Bool {
        UUID(uuidString: id) != nil && version > 0 && publisher.isValid && recipe.isValid
            && recipeID == recipe.id && provenance.isValid
            && (publishedVersion == nil || publishedVersion! > 0)
    }
    var visibilitySummary: String {
        switch status {
        case .published: "Published · version \(version)"
        case .archived: "Archived · version \(version)"
        case .draft:
            if let publishedVersion { "Draft \(version) · version \(publishedVersion) is live" }
            else { "Draft · version \(version)" }
        }
    }
}

struct MarketplaceInventoryEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let listingID: String
    let version: Int
    let recipeID: String
    let recipe: CompanionItemPackage
    let publisher: MarketplaceAccount
    let provenance: MarketplaceProvenance
    let acquiredAt: String
    var acquiredDate: Date? { try? Date.ISO8601FormatStyle().parse(acquiredAt) }
    var isValid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: listingID) != nil && version > 0
            && recipeID == recipe.id && recipe.isValid && publisher.isValid && provenance.isValid
    }
}

struct MarketplacePage<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let total: Int
    let limit: Int
    let offset: Int
    var isValid: Bool { total >= 0 && (1...100).contains(limit) && (0...10_000).contains(offset) && items.count <= limit }
}

struct MarketplaceHealth: Decodable, Sendable {
    let service: String
    let apiVersion: Int
    let mode: String
    let commerce: Bool
    let recipeSchema: String
    let maximumRecipeBytes: Int
    var isSupported: Bool {
        service == "archi-marketplace" && apiVersion == 1 && mode == "development" && !commerce
            && recipeSchema == CompanionItemPackage.currentSchema && maximumRecipeBytes == CompanionItemPackage.maximumBytes
    }
}

struct MarketplaceAccountResponse: Decodable, Sendable { let account: MarketplaceAccount }
struct MarketplaceSession: Decodable, Sendable {
    let account: MarketplaceAccount
    let token: String
    let expiresAt: String
}
struct MarketplaceListingResponse: Decodable, Sendable { let listing: MarketplaceListing }
struct MarketplaceAcquisitionResponse: Decodable, Sendable {
    let entry: MarketplaceInventoryEntry
    let alreadyAcquired: Bool
}
struct MarketplaceSignOutResponse: Decodable, Sendable { let signedOut: Bool }

struct MarketplaceServiceError: Error, LocalizedError, Sendable {
    let code: String
    let status: Int?
    var errorDescription: String? {
        switch code {
        case "endpoint": "Use a loopback HTTP address such as http://127.0.0.1:47831."
        case "unsupported_service": "This address is not a compatible ARCHi development catalog."
        case "unauthorized": "Your session ended. Sign in again to access your account library."
        case "handle_taken": "That handle already has an account. Sign in or choose another handle."
        case "version_conflict", "state_conflict": "This listing changed. Refresh My listings and reopen its latest version before saving."
        case "listing_changed": "This published version changed. Refresh the catalog before acquiring it."
        case "validation_failed", "invalid_request": "Check the required fields and their limits before trying again."
        case "not_found": "This listing or version is unavailable to this account."
        case "digest_mismatch": "The downloaded recipe does not match its listing. Nothing was installed."
        case "response_too_large", "invalid_response": "The catalog returned an invalid response. Nothing was installed."
        case "capacity_reached", "rate_limited": "The development service has reached a limit. Try again later."
        default: "The catalog could not complete this request. Refresh or try again."
        }
    }
}
