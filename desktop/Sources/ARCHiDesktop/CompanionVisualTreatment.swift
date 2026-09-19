import AppKit
import ImageIO
import CryptoKit

enum CompanionVisualTreatment: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case pearlStudy = "Pearl study"
    case protoStudy = "Proto expression"
    var id: String { rawValue }
}

/// Reviewed bundled studies, rendered through the same native image path.
/// This is not an arbitrary-file importer or another appearance store.
@MainActor
enum CompanionVisualAsset {
    struct BundledBody: Equatable {
        let filename: String
        let digest: String
        // Complete digest participates in the cache key, independently of the
        // human-facing version and the older Original/Pearl finish preference.
        var canonicalIdentity: String { "\(filename)\nsha256=\(digest)" }
    }

    static func tealBody(for form: CompanionForm) -> BundledBody? {
        switch form {
        case .constellation:
            BundledBody(filename: "archi-teal-constellation-v1", digest: "505e40c2f279fe89c75f066f66ad38c86696e0d4a775c5245f268ee984b1bf00")
        case .sprout:
            BundledBody(filename: "archi-teal-sprout-v1", digest: "222ec7843b58f5f3c09ce99cbaffe3dd0f662737c66c75608298b1e30afde93a")
        case .ribbonSpirit:
            BundledBody(filename: "archi-teal-ribbon-spirit-v1", digest: "4a75407d8b4248ef7282e366d9486470f43e282f914e449b17c1fde358d1534d")
        case .geode:
            BundledBody(filename: "archi-teal-geode-v1", digest: "4cb2535fb127abf011c90321b4f7abe0231c4dd94a987406c65b081a5810a397")
        default: nil
        }
    }

    static let revision = "pearl-study-v1-b47816dc"
    static let digest = "b47816dc3c72078b2456f4e1b42de071d12f23a4782048f1a7b0ab48e3029198"
    static let filename = "archi-pearl-study-v1"
    static let lumenRevision = "lumen-pearl-v1-5bb6b3fd"
    static let lumenDigest = "5bb6b3fd2774be1227519f2d341f441e64488e2e4b966258ec92c47eb98f8a97"
    static let lumenFilename = "archi-lumen-pearl-v1"
    static let maximumBytes = 1_400_000
    static let lightSeedFilename = "archi-ball-of-light-v1"
    static let lightSeedDigest = "bc8b05e36156af6bb28459fa160b118315c14d1d319e04c23d861b7416d3018b"
    static let lightSeedImage = load(name: lightSeedFilename, digest: lightSeedDigest)
    static let hamptonSeedFilename = "hampton-liminal-seed-v1"
    static let hamptonSeedDigest = "2f8ac5d79dae36bed3e91cbd55f53b2f86d5317b464c119d9c14d37512044c18"
    static let hamptonSeedImage = load(name: hamptonSeedFilename, digest: hamptonSeedDigest)
    static let hamptonGarnetFilename = "hampton-liminal-garnet-v1"
    static let hamptonGarnetDigest = "4926755798476430159df3923399242d0f564ea11fa3f8895f769f60655128a9"
    static let hamptonGarnetImage = load(name: hamptonGarnetFilename, digest: hamptonGarnetDigest)
    static let kinSeedFilename = "kin-core-seed-blender-v2"
    static let kinSeedDigest = "02066c89c597edf6b0f9d3c9f5706323cfefa8163c94b8407ec48cd7e57bf5e6"
    static let kinSeedImage = load(name: kinSeedFilename, digest: kinSeedDigest)
    static let kinFirstLightFilename = "kin-first-light-blender-v1"
    // Replaced only after the final Blender portrait passes source review.
    static let kinFirstLightDigest = "96dcfec5654287a22c5d53357dcc47dc7a6a92cd4458da381c45fe074f32de2d"
    static let kinFirstLightImage = load(name: kinFirstLightFilename, digest: kinFirstLightDigest)
    static let protoFilename = "archi-proto-blender-v1"
    static let protoDigest = "c1de08a1afb9532d3cd459f9d166dcc58f4d05852ba3fb98d6c3f4bb3319b338"
    static let protoImage = load(name: protoFilename, digest: protoDigest)
    static func firstLightImage(treatment: CompanionVisualTreatment) -> NSImage? {
        treatment == .protoStudy ? (protoImage ?? kinFirstLightImage) : kinFirstLightImage
    }
    static func usesProto(_ treatment: CompanionVisualTreatment) -> Bool {
        treatment == .protoStudy && protoImage != nil
    }
    static var resourceURL: URL? {
        resourceURL(named: filename)
    }
    static func resourceURL(named name: String) -> URL? {
        // Packaged apps must not silently load an asset from a developer's .build
        // directory. SwiftPM's module bundle remains the resource owner in tests.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL?.appendingPathComponent("CompanionArt/\(name).png")
        }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "CompanionArt")
    }
    static let image = load(name: filename, digest: digest)
    static let lumenImage = load(name: lumenFilename, digest: lumenDigest)
    private static let tealImages: [CompanionForm: NSImage] = {
        var images: [CompanionForm: NSImage] = [:]
        for form in CompanionForm.allCases {
            if let body = tealBody(for: form), let image = load(name: body.filename, digest: body.digest) {
                images[form] = image
            }
        }
        return images
    }()
    private static func load(name: String, digest: String) -> NSImage? {
        guard let url = resourceURL(named: name),
              let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount > 0, byteCount < maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return verifiedImage(data, expectedDigest: digest)
    }

    static func verifiedImage(_ data: Data, expectedDigest: String) -> NSImage? {
        guard data.count > 0, data.count < maximumBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedDigest else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> NSImage? {
        guard data.count < maximumBytes,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int) == 512,
              (properties[kCGImagePropertyPixelHeight] as? Int) == 512,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 512, height: 512))
    }

    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        (family == nil && tealBody(for: form) != nil)
            || (family == nil && form == .companion && treatment == .protoStudy)
            || (form == .companion && (family == nil || family == .lumen) && treatment == .pearlStudy)
    }

    static func resolvedImage(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> NSImage? {
        if family == nil, tealBody(for: form) != nil { return tealImages[form] }
        guard applies(form: form, family: family, treatment: treatment) else { return nil }
        if family == nil && treatment == .protoStudy { return protoImage }
        return family == .lumen ? lumenImage : image
    }

    static func label(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                      recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                      equipment: CompanionEquipment = .empty, seedColor: CompanionSeedColor = .original) -> String {
        let label = baseLabel(form: form, family: family, treatment: treatment, recipe: recipe, naturalVariation: naturalVariation)
        let coloredLabel = seedColor != .original && SeedColorRendering.applies(form: form, family: family)
            ? "\(label) · \(seedColor.title)" : label
        let combined = equipment.item.map { "\(coloredLabel) · \($0.title)" } ?? coloredLabel
        // The hosted bridge measures JavaScript string length in UTF-16 units.
        // Keep short legacy labels exact and never split an emoji or grapheme.
        guard combined.utf16.count > 80 else { return combined }
        var result = "", units = 0
        for character in combined {
            let count = String(character).utf16.count
            guard units + count <= 79 else { break }
            result.append(character)
            units += count
        }
        return result + "…"
    }

    private static func baseLabel(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                                  recipe: CompanionAppearanceRecipe?, naturalVariation: CompanionNaturalVariation?) -> String {
        if family == nil && form == .hamptonSeed { return "Hampton · Liminal Seed" }
        if family == nil && form == .corePearl { return "ARCHi · Ball of Light" }
        if family == nil && form == .particleSeed { return "KIN · Particle Seed look" }
        if family == nil, tealBody(for: form) != nil { return form.rawValue }
        if family == nil, form == .kin, usesProto(treatment) { return "First Light · Proto expression" }
        let base: String
        if resolvedImage(form: form, family: family, treatment: treatment) != nil {
            base = "\(family?.title ?? form.rawValue) · \(treatment.rawValue)"
        } else {
            base = family?.title ?? form.rawValue
        }
        if let family, let recipe, recipe.family == family {
            return "\(base) · \(recipe.fingerprint.prefix(8)) · \(recipe.role.title), \(recipe.helpStyle.title)"
        }
        guard let variation = effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation) else { return base }
        return "\(base) · Individual \(variation.fingerprint.prefix(8))"
    }

    /// Keep presentation support and cache identity in agreement. Authored forms
    /// without a natural drawing path remain unchanged, as do kept legacy recipes.
    static func effectiveNaturalVariation(form: CompanionForm, family: EvolutionFamily?, recipe: CompanionAppearanceRecipe?,
                                          naturalVariation: CompanionNaturalVariation?) -> CompanionNaturalVariation? {
        guard form == .companion, family == nil || family == .lumen,
              !(family != nil && recipe?.family == family) else { return nil }
        return naturalVariation
    }

    static func appearanceID(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                             recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                             equipment: CompanionEquipment = .empty,
                             assetAvailable: Bool? = nil, seedColor: CompanionSeedColor = .original) -> String {
        let original = baseAppearanceID(form: form, family: family, treatment: treatment, recipe: recipe,
            naturalVariation: naturalVariation, assetAvailable: assetAvailable)
        let base = SeedColorRendering.identity(base: original, form: form, family: family, color: seedColor)
        guard !equipment.isEmpty else { return base }
        // Include the complete resolved body and equipment inputs, while leaving
        // room for the hosted bridge's expression revision within 100 characters.
        let canonical = "archi-equipped-appearance/v1\nappearance=\(base)\n\(equipment.canonicalIdentity)"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "e1-\(digest)"
    }

    private static func baseAppearanceID(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                                         recipe: CompanionAppearanceRecipe?, naturalVariation: CompanionNaturalVariation?,
                                         assetAvailable: Bool?) -> String {
        if family == nil && form == .hamptonSeed {
            return (assetAvailable ?? (hamptonSeedImage != nil)) ? "h1-\(hamptonSeedDigest)" : "hampton-liminal-native-fallback-v1"
        }
        if family == nil && form == .corePearl {
            return (assetAvailable ?? (lightSeedImage != nil)) ? "l1-\(lightSeedDigest)" : "optical-light-v1:Core pearl"
        }
        if family == nil && form == .particleSeed {
            return (assetAvailable ?? (kinSeedImage != nil)) ? "ps-\(kinSeedDigest)" : "kin-particle-native-v1"
        }
        if family == nil, form.isOpticalLight {
            // Native geometry has a revision just like bundled artwork. The same
            // fixed frame supplies desktop previews and the retained image bridge.
            return "optical-light-v1:\(form.rawValue)"
        }
        if family == nil, form == .kinSeed {
            return (assetAvailable ?? (kinSeedImage != nil)) ? "k2-\(kinSeedDigest)" : "kin-core-seed-native-fallback-v1"
        }
        if family == nil, form == .kin {
            if treatment == .protoStudy, assetAvailable ?? (protoImage != nil) {
                return "p1-\(protoDigest)"
            }
            // Both paths stay inside KinFirstLightPortrait, preserving the same
            // attention clock and core-anchored light. Only the resting body is
            // cached; a missing or unverified asset uses the retained drawing.
            return (assetAvailable ?? (kinFirstLightImage != nil))
                ? "kf1-\(kinFirstLightDigest)" : "kin-first-light-native-v2"
        }
        if family == nil, let body = tealBody(for: form) {
            let available = assetAvailable ?? (tealImages[form] != nil)
            let presentation = available ? body.canonicalIdentity : "local-fallback/v1\nform=\(form.rawValue)"
            let canonical = "archi-teal-body/v1\n\(presentation)\n"
            let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return "t1-\(hash)"
        }
        let base = "\(form.rawValue):\(family?.rawValue ?? "origin")"
        let available = assetAvailable ?? (resolvedImage(form: form, family: family, treatment: treatment) != nil)
        let selectedRevision = family == .lumen ? lumenRevision : revision
        let appearance = applies(form: form, family: family, treatment: treatment) && available
            ? (treatment == .protoStudy && family == nil ? "p1-\(protoDigest)" : "\(base):\(selectedRevision)") : base
        if let family, let recipe, recipe.family == family {
            // Habitat limits IDs to 100 characters, including a possible expression
            // suffix. Hash the complete inputs; neither the recipe nor asset identity
            // is truncated. The 67-character ID leaves room for UInt64.max revisions.
            let canonical = "archi-individual-appearance/v1\nappearance=\(appearance)\nrecipe=\(recipe.fingerprint)\n"
            let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return "i1-\(digest)"
        }
        guard let variation = effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation) else { return appearance }
        let canonical = "archi-natural-appearance/v1\nappearance=\(appearance)\nnatural=\(variation.fingerprint)\n"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "n1-\(digest)"
    }
}
