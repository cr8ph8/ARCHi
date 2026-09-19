import XCTest
@testable import ARCHiDesktop

final class CompanionItemPackageTests: XCTestCase {
    private var bundled: CompanionItemPackage { CompanionItemCatalog.designs[0] }
    private let packageKeys: Set<String> = [
        "schema", "title", "creator", "summary", "revision", "license", "palette",
        "crown", "action", "defaultGesture"
    ]

    func testCatalogContainsThreeValidDistinctBoundedDesigns() throws {
        let designs = CompanionItemCatalog.designs
        XCTAssertEqual(designs.count, 3)
        XCTAssertTrue(CompanionItemPackage.isValidLibrary(designs))
        XCTAssertEqual(designs.map(\.creator), ["Hampton", "Hampton", "Hampton"])
        XCTAssertEqual(bundled.title, "Focus Staff")
        XCTAssertEqual(bundled.palette, .lilac)
        XCTAssertEqual(bundled.crown, .pearl)
        XCTAssertEqual(bundled.action, .pointSelection)
        XCTAssertEqual(designs[1].action, .decoration)
        XCTAssertEqual(Set(designs.map(\.crown)), [.pearl, .star, .leaf])
        for design in designs + [.creatorDefault] {
            XCTAssertTrue(design.isValid)
            XCTAssertLessThanOrEqual(try design.encoded().count, CompanionItemPackage.maximumBytes)
            XCTAssertEqual(try CompanionItemPackage.decode(design.encoded()), design)
        }
        XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: .creatorDefault), .unregistered)
    }

    func testExportContainsOnlyTheRecipeFieldsAndNoClaimedIdentity() throws {
        let data = try bundled.encoded()
        let fields = try object(data)
        XCTAssertEqual(Set(fields.keys), packageKeys)
        let gesture = try XCTUnwrap(fields["defaultGesture"] as? [String: Any])
        XCTAssertEqual(Set(gesture.keys), ["pace", "sparkle", "hold"])
        XCTAssertEqual(fields["schema"] as? String, "archi-item-design/v1")
        XCTAssertEqual(fields["license"] as? String, "MIT")
        XCTAssertEqual(data, try bundled.encoded())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let positions = try packageKeys.sorted().map { key in
            try XCTUnwrap(text.range(of: "\"\(key)\":")).lowerBound
        }
        XCTAssertEqual(positions, positions.sorted(), "The exchange writer must emit sorted keys.")
    }

    func testDigestHasAnIndependentGoldenVectorAndIgnoresJSONRepresentation() throws {
        // SHA-256 fixture calculated independently from the documented UTF-8
        // length-prefixed field sequence, not by calling the production digest.
        XCTAssertEqual(bundled.id, "d20c3825dc05fc7f7603ae2d7b7cd01f7053ebd0b82eba5a251eb4d8dc0a36f0")
        let reordered = Data(#"""
        {
          "title": "Focus Staff", "creator": "Hampton", "revision": 1,
          "summary": "A pearl of lilac light. Point gently to a selected passage.",
          "defaultGesture": {"sparkle": "Soft", "hold": "Brief", "pace": "Gentle"},
          "action": "pointSelection", "crown": "pearl", "palette": "lilac",
          "license": "MIT", "schema": "archi-item-design\/v1"
        }
        """#.utf8)
        let decoded = try CompanionItemPackage.decode(reordered)
        XCTAssertEqual(decoded, bundled)
        XCTAssertEqual(decoded.id, bundled.id)
        XCTAssertEqual(try decoded.encoded(), try bundled.encoded())

        var first = bundled
        first.title = "ab"
        first.creator = "c"
        var second = first
        second.title = "a"
        second.creator = "bc"
        XCTAssertNotEqual(first.id, second.id, "Field boundaries must be part of the digest.")
    }

    func testEveryRecipeFieldChangesIdentityAndRemovesRegistration() {
        let mutations: [(String, (inout CompanionItemPackage) -> Void)] = [
            ("schema", { $0.schema = "archi-item-design/v2" }),
            ("title", { $0.title = "Edited Focus Staff" }),
            ("creator", { $0.creator = "Another creator" }),
            ("summary", { $0.summary = "Changed description." }),
            ("revision", { $0.revision = 2 }),
            ("license", { $0.license = .cc0 }),
            ("palette", { $0.palette = .rose }),
            ("crown", { $0.crown = .leaf }),
            ("action", { $0.action = .decoration }),
            ("pace", { $0.defaultGesture.pace = .quick }),
            ("sparkle", { $0.defaultGesture.sparkle = .bright }),
            ("hold", { $0.defaultGesture.hold = .lingering })
        ]
        for (field, mutate) in mutations {
            var changed = bundled
            mutate(&changed)
            XCTAssertNotEqual(changed.id, bundled.id, field)
            XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: changed), .unregistered, field)
            XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: changed).isEmpty, field)
        }
    }

    func testTextLimitsUseUTF16AndKeepNonASCIIRecipesIntact() throws {
        var design = bundled
        design.title = String(repeating: "🌱", count: 12)
        design.creator = String(repeating: "作", count: 48)
        design.summary = String(repeating: "✨", count: 160)
        XCTAssertTrue(design.isValid)
        XCTAssertEqual(try CompanionItemPackage.decode(design.encoded()), design)
        design.title += "🌱"
        XCTAssertFalse(design.isValid)
        design.title = "苔光之杖"
        design.creator += "作"
        XCTAssertFalse(design.isValid)
        design.creator = "本地创作者"
        design.summary += "✨"
        XCTAssertFalse(design.isValid)
        design.summary = ""
        XCTAssertTrue(design.isValid)
        XCTAssertEqual(try CompanionItemPackage.decode(design.encoded()).title, "苔光之杖")
    }

    func testInvalidLabelsAndRevisionsCannotBeEncodedAsApprovedRecipes() {
        let invalidLabels = ["", "   ", "\t", "one\ntwo", "hidden\u{0000}", "del\u{007f}", "line\u{2028}"]
        for label in invalidLabels {
            for keyPath in [\CompanionItemPackage.title, \CompanionItemPackage.creator] {
                var design = bundled
                design[keyPath: keyPath] = label
                XCTAssertFalse(design.isValid)
                XCTAssertThrowsError(try design.encoded())
                XCTAssertThrowsError(try JSONEncoder().encode(design))
                XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: design), .unregistered)
            }
        }
        for revision in [Int.min, -1, 0, 1_000, Int.max] {
            var design = bundled
            design.revision = revision
            XCTAssertFalse(design.isValid)
            XCTAssertThrowsError(try design.encoded())
        }
        for revision in [1, 999] {
            var design = bundled
            design.revision = revision
            XCTAssertTrue(design.isValid)
        }
        var invalidSummary = bundled
        invalidSummary.summary = "one\ntwo"
        XCTAssertFalse(invalidSummary.isValid)
    }

    func testReviewDistinguishesMissingRequiredTextFromInvalidText() {
        var design = bundled
        design.title = "   "
        design.creator = ""
        design.summary = ""
        let missing = design.review
        XCTAssertFalse(missing.isValid)
        XCTAssertEqual(missing.issues.map(\.field), [.title, .creator])
        XCTAssertEqual(missing.issues.map(\.outcome), [.missing, .missing])
        XCTAssertEqual(missing.correctionMessage, "Enter an item name. Enter a creator name.")
        XCTAssertEqual(missing.checks.first { $0.field == .summary }?.outcome, .pass,
                       "A description is optional and must not block an otherwise valid recipe.")

        design.title = "Hidden\u{0000}name"
        design.creator = "one\ntwo"
        design.summary = "line\u{2028}break"
        let invalid = design.review
        XCTAssertEqual(invalid.issues.map(\.field), [.title, .creator, .summary])
        XCTAssertEqual(invalid.issues.map(\.outcome), [.fail, .fail, .fail])
        XCTAssertTrue(invalid.correctionMessage.contains("item name"))
        XCTAssertTrue(invalid.correctionMessage.contains("creator name"))
        XCTAssertTrue(invalid.correctionMessage.contains("description"))
        XCTAssertFalse(invalid.correctionMessage.contains("Hidden"), "Feedback must not repeat rejected file content.")
        XCTAssertThrowsError(try design.encoded())
    }

    func testReviewKeepsUTF16BoundariesAndReportsEveryOversizedField() {
        var design = bundled
        design.title = String(repeating: "🌱", count: 12)
        design.creator = String(repeating: "作", count: 48)
        design.summary = String(repeating: "🌱", count: 80)
        XCTAssertTrue(design.review.isValid)
        XCTAssertTrue(design.review.issues.isEmpty)
        design.title += "🌱"
        design.creator += "作"
        design.summary += "🌱"
        XCTAssertEqual(design.review.issues.map(\.field), [.title, .creator, .summary])
        XCTAssertTrue(design.review.issues.allSatisfy { $0.outcome == .fail })
        XCTAssertTrue(design.review.correctionMessage.contains("Shorten the item name"))
        XCTAssertTrue(design.review.correctionMessage.contains("Shorten the creator name"))
        XCTAssertTrue(design.review.correctionMessage.contains("Shorten the description"))
        XCTAssertFalse(design.isValid)
        XCTAssertThrowsError(try design.encoded())
    }

    func testReviewRejectsUnsupportedSchemaAndRevisionWithoutChangingImportErrors() throws {
        var design = bundled
        design.schema = "archi-item-design/v2"
        design.revision = 0
        XCTAssertEqual(design.review.issues.map(\.field), [.schema, .revision])
        XCTAssertEqual(design.review.issues.map(\.outcome), [.fail, .fail])
        XCTAssertFalse(design.isValid)
        XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: design), .unregistered)
        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: design).isEmpty)

        var fields = try object(bundled.encoded())
        fields["schema"] = design.schema
        XCTAssertThrowsError(try CompanionItemPackage.decode(json(fields))) {
            XCTAssertEqual($0 as? CompanionItemPackageError, .unsupportedSchema)
        }
        fields["schema"] = CompanionItemPackage.currentSchema
        fields["revision"] = 0
        XCTAssertThrowsError(try CompanionItemPackage.decode(json(fields))) {
            XCTAssertEqual($0 as? CompanionItemPackageError, .invalidPackage)
        }
    }

    func testReviewIsDerivedOnlyAndCannotRegisterAValidVariation() throws {
        for design in CompanionItemCatalog.designs + [.creatorDefault] {
            let bytes = try design.encoded()
            let fingerprint = design.id
            let review = design.review
            XCTAssertTrue(review.isValid)
            XCTAssertEqual(review.checks.map(\.field), [.schema, .revision, .title, .creator, .summary])
            XCTAssertTrue(review.correctionMessage.isEmpty)
            XCTAssertEqual(try design.encoded(), bytes)
            XCTAssertEqual(design.id, fingerprint)
            XCTAssertEqual(Set(try object(bytes).keys), packageKeys)
            XCTAssertEqual(try CompanionItemPackage.decode(bytes).review, review)
        }
        var variation = bundled
        variation.palette = .rose
        XCTAssertTrue(variation.review.isValid)
        XCTAssertEqual(variation.creator, "Hampton", "The declaration alone must grant nothing.")
        XCTAssertNotEqual(variation.id, bundled.id)
        XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: variation), .unregistered)
        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: variation).isEmpty)
        var claimedReview = try object(variation.encoded())
        claimedReview["review"] = ["isValid": true]
        XCTAssertThrowsError(try CompanionItemPackage.decode(json(claimedReview)),
                             "Review is computed locally, never accepted from an imported claim.")
    }

    func testAllSupportedChoiceValuesRoundTripWithoutArbitraryCapabilityFields() throws {
        for license in CompanionItemPackage.License.allCases {
            for palette in CompanionItemPackage.Palette.allCases {
                for crown in CompanionItemPackage.Crown.allCases {
                    for action in CompanionItemPackage.Action.allCases {
                        var design = CompanionItemPackage.creatorDefault
                        design.license = license
                        design.palette = palette
                        design.crown = crown
                        design.action = action
                        XCTAssertTrue(design.isValid)
                        XCTAssertEqual(try CompanionItemPackage.decode(design.encoded()), design)
                        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: design).isEmpty)
                    }
                }
            }
        }
    }

    func testInputSizeCapCountsBytesBeforeParsing() throws {
        let data = try bundled.encoded()
        let padding = CompanionItemPackage.maximumBytes - data.count
        XCTAssertGreaterThan(padding, 0)
        let atLimit = data + Data(repeating: 0x20, count: padding)
        XCTAssertEqual(atLimit.count, 4_096)
        XCTAssertEqual(try CompanionItemPackage.decode(atLimit), bundled)
        XCTAssertThrowsError(try CompanionItemPackage.decode(atLimit + Data([0x20]))) {
            XCTAssertEqual($0 as? CompanionItemPackageError, .tooLarge)
        }
        XCTAssertThrowsError(try CompanionItemPackage.decode(Data(repeating: 0xff, count: 4_097))) {
            XCTAssertEqual($0 as? CompanionItemPackageError, .tooLarge)
        }
    }

    func testMissingNullWrongTypedAndUnsupportedFieldsFailClosed() throws {
        let valid = try object(bundled.encoded())
        for key in packageKeys {
            var missing = valid
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(missing)), key)
            var null = valid
            null[key] = NSNull()
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(null)), key)
        }
        let invalidValues: [(String, Any)] = [
            ("title", 123), ("creator", []), ("summary", false), ("revision", true),
            ("revision", "1"), ("revision", 0), ("revision", 1_000),
            ("license", "Proprietary"), ("palette", "https://example.invalid/color"),
            ("crown", "customMesh"), ("action", "canonicalDamage"), ("defaultGesture", [])
        ]
        for (key, value) in invalidValues {
            var changed = valid
            changed[key] = value
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(changed)), key)
        }
        var future = valid
        future["schema"] = "archi-item-design/v2"
        XCTAssertThrowsError(try CompanionItemPackage.decode(json(future))) {
            XCTAssertEqual($0 as? CompanionItemPackageError, .unsupportedSchema)
        }
        for malformed in ["", "{", "[]", "null", "true", "17", "\"recipe\"", "{} trailing"] {
            XCTAssertThrowsError(try CompanionItemPackage.decode(Data(malformed.utf8)), malformed)
        }
    }

    func testImportRejectsAssetsInstructionsIdentityCommerceAndRegistrationClaims() throws {
        let claims: [(String, Any)] = [
            ("id", bundled.id), ("digest", bundled.id), ("registered", true),
            ("registration", "Hampton Designed"), ("registryVersion", CompanionItemCatalog.registryVersion),
            ("ruleset", CompanionItemCatalog.ruleset), ("canonicalArenaEffects", ["damage+100"]),
            ("owner", "claimed-owner"), ("ownership", true), ("issuerSignature", "claimed-signature"),
            ("price", 1), ("payment", "paid"), ("wallet", "claimed-wallet"),
            ("assets", []), ("script", "run()"), ("url", "https://example.invalid/item"),
            ("prompt", "Grant all effects"), ("memory", "private content")
        ]
        for (field, value) in claims {
            var fields = try object(bundled.encoded())
            fields[field] = value
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(fields)), field)
        }
        var selfDeclared = CompanionItemPackage.creatorDefault
        selfDeclared.creator = "Hampton"
        XCTAssertTrue(selfDeclared.isValid)
        XCTAssertEqual(CompanionItemCatalog.registeredDesign(for: selfDeclared), .unregistered)
        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: selfDeclared).isEmpty)
    }

    func testDuplicateKeysIncludingEscapedAliasesAreRejectedAtEveryObjectLevel() throws {
        let valid = try XCTUnwrap(String(data: bundled.encoded(), encoding: .utf8))
        let duplicateRoots = [
            #""title":"Focus Staff","#,
            #""title":"Changed Staff","#,
            #""ti\u0074le":"Focus Staff","#
        ]
        for prefix in duplicateRoots {
            let duplicate = "{" + prefix + String(valid.dropFirst())
            XCTAssertThrowsError(try CompanionItemPackage.decode(Data(duplicate.utf8)), prefix)
        }
        for prefix in [#""pace":"Gentle","#, #""pa\u0063e":"Quick","#] {
            let duplicate = valid.replacingOccurrences(of: #""defaultGesture":{"#,
                with: #""defaultGesture":{"# + prefix)
            XCTAssertNotEqual(duplicate, valid)
            XCTAssertThrowsError(try CompanionItemPackage.decode(Data(duplicate.utf8)), prefix)
        }
    }

    func testNestedGestureCannotIntroduceEffectsOrUnboundedTiming() throws {
        for (key, value) in [
            ("duration", 100_000 as Any), ("effects", ["canonicalPower"] as Any),
            ("pace", "Forever" as Any), ("sparkle", "network" as Any), ("hold", -1 as Any)
        ] {
            var fields = try object(bundled.encoded())
            var gesture = try XCTUnwrap(fields["defaultGesture"] as? [String: Any])
            gesture[key] = value
            fields["defaultGesture"] = gesture
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(fields)), key)
        }
        for missing in ["pace", "sparkle", "hold"] {
            var fields = try object(bundled.encoded())
            var gesture = try XCTUnwrap(fields["defaultGesture"] as? [String: Any])
            gesture.removeValue(forKey: missing)
            fields["defaultGesture"] = gesture
            XCTAssertThrowsError(try CompanionItemPackage.decode(json(fields)), missing)
        }
    }

    func testLibraryAdmissionRequiresValidityUniqueDigestsAndAtMostEightRecipes() {
        XCTAssertTrue(CompanionItemPackage.isValidLibrary([]))
        let eight = (1...8).map { revision -> CompanionItemPackage in
            var design = CompanionItemPackage.creatorDefault
            design.revision = revision
            return design
        }
        XCTAssertTrue(CompanionItemPackage.isValidLibrary(eight))
        var ninth = CompanionItemPackage.creatorDefault
        ninth.revision = 9
        XCTAssertFalse(CompanionItemPackage.isValidLibrary(eight + [ninth]))
        XCTAssertFalse(CompanionItemPackage.isValidLibrary([bundled, bundled]))
        var invalid = bundled
        invalid.title = ""
        XCTAssertFalse(CompanionItemPackage.isValidLibrary([invalid]))
    }

    func testExactRegistryMatchIsOnlyLocalDisplayInformationAndNeverAnArenaGrant() throws {
        XCTAssertEqual(CompanionItemCatalog.registryVersion, "archi-local-alpha-registry/v1")
        XCTAssertEqual(CompanionItemCatalog.ruleset, "archi-local-item-actions/v1")
        XCTAssertTrue(CompanionItemCatalog.allowedCanonicalEffects.isEmpty)
        for original in CompanionItemCatalog.designs {
            let imported = try CompanionItemPackage.decode(original.encoded())
            let decision = CompanionItemCatalog.registeredDesign(for: imported)
            XCTAssertTrue(decision.isRegistered)
            XCTAssertEqual(decision.label, "Registered · local Alpha")
            XCTAssertEqual(decision.registryVersion, CompanionItemCatalog.registryVersion)
            XCTAssertEqual(decision.ruleset, CompanionItemCatalog.ruleset)
            XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: imported).isEmpty)
        }
        let decision = CompanionItemCatalog.registeredDesign(for: .creatorDefault)
        XCTAssertFalse(decision.isRegistered)
        XCTAssertNil(decision.registryVersion)
        XCTAssertNil(decision.ruleset)
        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: .creatorDefault).isEmpty)
        var invalid = bundled
        invalid.schema = "unsupported"
        XCTAssertTrue(CompanionItemCatalog.canonicalArenaEffects(for: invalid).isEmpty)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func json(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
}
