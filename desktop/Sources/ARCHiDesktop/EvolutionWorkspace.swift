import SwiftUI

@MainActor
struct EvolutionWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var evolution: EvolutionStore
    @State private var roleChoice: EvolutionRole?
    @State private var helpChoice: EvolutionHelpStyle?
    @State private var showForget = false
    @State private var showReplace = false
    @State private var showLoad = false
    @State var lifeRecordsExpanded = false
    @State var usefulnessRecordsExpanded = false

    private var shownForm: CompanionForm { store.preferences.form }
    private var shownFamily: EvolutionFamily? { evolution.previewFamily ?? evolution.activeFamily }
    private var showsPearlFamily: Bool { shownFamily == .lumen || (shownFamily == nil && shownForm == .companion) }
    private var shownName: String { showsPearlFamily ? "Pearl family" : shownFamily?.title ?? shownForm.rawValue }
    private var shownRecipe: CompanionAppearanceRecipe? {
        if let recipe = evolution.proposal?.appearanceRecipe, recipe.family == shownFamily {
            return recipe
        }
        guard evolution.previewFamily == nil,
              let recipe = evolution.activeAppearanceRecipe, recipe.family == shownFamily else { return nil }
        return recipe
    }
    private var shownNaturalVariation: CompanionNaturalVariation? {
        CompanionVisualAsset.effectiveNaturalVariation(form: shownForm, family: shownFamily,
            recipe: shownRecipe, naturalVariation: evolution.naturalVariation)
    }
    private var supportsNaturalDetails: Bool { shownForm == .companion && (shownFamily == nil || shownFamily == .lumen) }
    private var lifeRecordSummary: String {
        let requests = evolution.usefulReceipts.count
        let lessons = evolution.usefulReceipts.filter { $0.lessonUse != nil }.count
        return "\(requests) useful request\(requests == 1 ? "" : "s") · \(lessons) lesson reference\(lessons == 1 ? "" : "s") retained"
    }
    private var individualDetailValue: String {
        if shownRecipe != nil { return "Earlier kept details" }
        if shownNaturalVariation != nil { return "Present from the beginning" }
        return supportsNaturalDetails ? "Waiting for your Journey" : "Standard form study"
    }
    private var individualDetailExplanation: String {
        if shownRecipe != nil { return "This form retains its earlier reviewed appearance details. Its original reasons are available below." }
        if shownNaturalVariation != nil { return "Subtle tint, proportions, and markings come from the Journey's origin and stay consistent with that individual." }
        return supportsNaturalDetails
            ? "Opening your Journey brings its small, consistent individual details into this family."
            : "Natural individual details are currently supported on the Pearl companion and Lumen. This optional study uses its standard appearance."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if store.hasPersonalQiMon {
                QiMonCard(store: store)
                KinGrowthCard(store: store, evolution: evolution)
                WorkspaceRouteRow(title: "Unity Area", detail: store.unityPresentationUnavailableReason ?? "Visit your companion in 3D or enter the Arena.",
                    icon: "cube.transparent", identifier: "evolution.unity-area") { store.open(.unity) }
                kinBeginning
                knowledge
                lifeTogether
                DisclosureGroup("Saved development records") { continuity.padding(.top, 16) }
            } else {
            hero
            individualDetails
            knowledge
            DisclosureGroup("Optional larger form studies") { families.padding(.top, 16) }
                .accessibilityIdentifier("evolution-optional-form-studies")
            lifeTogether
            continuity
            }
        }
        .onAppear { roleChoice = evolution.confirmedRole; helpChoice = evolution.confirmedHelpStyle }
        .onChange(of: evolution.confirmedRole) { _, value in roleChoice = value }
        .onChange(of: evolution.confirmedHelpStyle) { _, value in helpChoice = value }
        .confirmationDialog("Forget evolution choices and saved history?", isPresented: $showForget, titleVisibility: .visible) {
            Button("Forget evolution", role: .destructive) { evolution.forget() }
        } message: { Text("This clears evolution preferences, usefulness records, and the kept form, then deletes its local save. Your documents, ordinary preferences, and game Journey stay separate.") }
        .confirmationDialog("Replace the unreadable evolution save?", isPresented: $showReplace, titleVisibility: .visible) {
            Button("Replace saved evolution", role: .destructive) { evolution.save(replacingInvalidFile: true) }
        } message: { Text("The existing file could not be validated. Replace it with the choices currently shown here.") }
        .confirmationDialog("Load saved evolution?", isPresented: $showLoad, titleVisibility: .visible) {
            Button("Load saved evolution") { evolution.load() }
        } message: { Text("This replaces the evolution choices in this session with the last saved version. Unsaved evolution changes will be lost.") }
    }

    private var kinBeginning: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Growing together", detail: "One \(store.activeQiMon?.name ?? "companion"), with the same name, core and Journey across forms.")
                developmentExplanation("Motion and light", systemImage: "sparkles",
                    detail: "Gentle movement and temporary light cues show what \(store.activeQiMon?.name ?? "your companion") is doing. They settle back into the existing form.")
                developmentExplanation("What you teach", systemImage: "text.bubble",
                    detail: "Your confirmed role and help style guide replies. Lessons you explicitly keep can help with matching local Qwen questions; you can correct or forget them.")
                developmentExplanation("What helped", systemImage: "checkmark.message",
                    detail: "Mark a reply about a shared document as useful, or confirm that a kept lesson helped. Inspect or withdraw that feedback in Life together, then Save evolution to retain the changes.")
                developmentExplanation("Growing into a form", systemImage: "leaf",
                    detail: store.activeQiMon?.character == .hampton
                        ? "Liminal’s potential is a starting direction. A new Seed has no earned later body yet; shared experience and reviewed evidence must come first."
                        : "First Light can follow a kept lesson you confirmed helped. Preview and Keep are your choices; Core Seed remains available. Stirring, Verse and Horizon are still design studies.")
                Button("Review kept lessons") { store.open(.memory) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("evolution-kept-lessons")
            }
        }.accessibilityIdentifier("evolution-kin-development")
    }

    private func developmentExplanation(_ title: String, systemImage: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(WorkspaceTheme.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lifeTogether: some View {
        DisclosureGroup(isExpanded: $lifeRecordsExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                sharedWork
                if !store.hasPersonalQiMon && store.allowsPlay { practice }
            }.padding(.top, 16)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Life together · inspect retained records")
                Text(lifeRecordSummary)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("evolution-life-record-counts")
            }
        }.accessibilityIdentifier("evolution-life-records")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(evolution.previewFamily == nil ? "Your companion" : "An optional form study", systemImage: "sparkle")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("ONE CONTINUING COMPANION").font(.system(size: 9, weight: .medium)).tracking(1.4)
            }.foregroundStyle(.white.opacity(0.82))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) { currentPresence; direction.frame(width: 270) }
                VStack(alignment: .leading, spacing: 20) { currentPresence; direction }
            }
            Divider().overlay(.white.opacity(0.1))
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted.circle.fill").foregroundStyle(.cyan.opacity(0.85))
                Text("Small differences belong to the individual. Your life together continues whichever appearance you choose.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.70))
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 25).fill(LinearGradient(
                colors: [Color(red: 0.07, green: 0.12, blue: 0.19), Color(red: 0.13, green: 0.12, blue: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.12)))
    }

    private var currentPresence: some View {
        VStack(spacing: 8) {
            CompanionPresenceArt(form: shownForm, family: shownFamily, size: 208, reduceMotion: true,
                treatment: store.preferences.visualTreatment, recipe: shownRecipe,
                naturalVariation: evolution.naturalVariation, equipment: store.preferences.equipment, seedColor: store.preferences.seedColor)
            Text(shownName).font(.system(size: 14, weight: .medium))
            Text(evolution.previewFamily == nil ? "YOUR INDIVIDUAL" : "APPEARANCE PREVIEW")
                .font(.system(size: 8)).tracking(1.5).foregroundStyle(.white.opacity(0.55))
        }.foregroundStyle(.white).frame(minWidth: 248).padding(.vertical, 5)
            .accessibilityIdentifier("evolution-current-individual")
    }

    private var direction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One family.\nYour individual.")
                .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(.white)
            Text(shownNaturalVariation != nil
                 ? "The same familiar Pearl silhouette, with subtle details belonging to this Journey from the beginning."
                 : individualDetailExplanation)
                .font(.system(size: 12)).lineSpacing(4).foregroundStyle(.white.opacity(0.72))
            if let candidate = evolution.proposal {
                Text("You chose the \(candidate.family.title) form study. Review it here, then decide whether to keep it.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
                Text("Recorded basis: \(candidate.basis.title).")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
                Button("Keep this form", systemImage: "checkmark") { evolution.keepEvolution(candidate) }
                    .buttonStyle(EvolutionPrimaryButtonStyle())
                    .accessibilityIdentifier("evolution-keep")
            } else {
                Button("Review chosen form", systemImage: "sparkles") { evolution.proposeEvolution() }
                    .buttonStyle(EvolutionPrimaryButtonStyle())
                    .disabled(evolution.confirmedFamily == nil)
                    .accessibilityIdentifier("evolution-propose")
                if evolution.confirmedFamily == nil {
                    Text("Optional larger form studies are available below.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
            }
            if evolution.previewFamily != nil {
                Button("Close preview") { evolution.dismissPreview() }.buttonStyle(.borderless).foregroundStyle(.white.opacity(0.78))
            }
            if evolution.activeFamily != nil {
                Button("Return to starting form") { store.returnEvolutionToStarter() }
                    .buttonStyle(.borderless).foregroundStyle(.white.opacity(0.78))
                    .accessibilityIdentifier("evolution-return")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var individualDetails: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 16) {
                individualFact(showsPearlFamily ? "Pearl family" : "Chosen form", value: shownName,
                    detail: "A recognizable family silhouette carries through the small differences between individuals.", symbol: "pawprint")
                Divider()
                individualFact("Individual details", value: individualDetailValue,
                    detail: individualDetailExplanation, symbol: "circle.dotted")
                if store.allowsPlay && supportsNaturalDetails && shownRecipe == nil && shownNaturalVariation == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Open Habitat & Arena to load your Journey's individual details.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("evolution-recipe-needs-journey")
                        Button("Open Habitat & Arena", systemImage: "leaf") { store.open(.play) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Open Habitat and Arena to load your Journey")
                            .accessibilityIdentifier("evolution-recipe-open-journey")
                    }
                }
                Divider()
                individualFact("Life together",
                    value: "\(evolution.usefulReceipts.count) useful work records · \(evolution.reviewedPractices.count) reviewed practices",
                    detail: "A record of moments you chose to keep. Appearance choices remain available at your own pace.", symbol: "leaf")
                Divider()
                individualFact("How I help",
                    value: "\(evolution.confirmedRole?.title ?? "Default role") · \(evolution.confirmedHelpStyle?.title ?? "Default help style")",
                    detail: "These optional preferences guide replies. They do not choose an individual's body.", symbol: "text.bubble")

                DisclosureGroup("Individual references and earlier appearance choices") {
                    VStack(alignment: .leading, spacing: 16) {
                        if let variation = evolution.naturalVariation {
                            Text("Journey \(variation.originDigest.prefix(12)) · Details \(variation.fingerprint.prefix(12))")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Journey origin \(variation.originDigest). Individual details fingerprint \(variation.fingerprint).")
                                .accessibilityIdentifier("evolution-natural-variation-reference")
                            if shownNaturalVariation == nil {
                                Text("These are the Journey's natural detail references. The currently shown form uses the appearance described above.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        if let recipe = evolution.proposal?.appearanceRecipe { recipeDetails(recipe, proposed: true) }
                        if let recipe = evolution.keptAppearanceRecipe { recipeDetails(recipe, proposed: false) }
                        if evolution.proposal?.appearanceRecipe == nil && evolution.keptAppearanceRecipe == nil {
                            Text("No earlier appearance recipe is active. Retained form history is available below.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12)
                }
            }
        }
        .accessibilityIdentifier("evolution-individual-details")
    }

    private func individualFact(_ title: String, value: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(WorkspaceTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .medium, design: .rounded))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }

    private func recipeDetails(_ recipe: CompanionAppearanceRecipe, proposed: Bool, identifier: String? = nil) -> some View {
        let historical = !proposed && evolution.activeAppearanceRecipe != recipe
        let kind = identifier ?? (proposed ? "proposed" : "kept")
        return VStack(alignment: .leading, spacing: 12) {
            Label(proposed ? "Proposed details" : "Kept details", systemImage: proposed ? "sparkles" : "checkmark.seal")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("evolution-recipe-\(kind)-title")
            Text("\(recipe.family.title) · \(recipe.role.title) · \(recipe.helpStyle.title)")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("evolution-recipe-\(kind)-choices")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { recipeOrigin(recipe, kind: kind); recipeFingerprint(recipe, kind: kind) }
                VStack(alignment: .leading, spacing: 5) { recipeOrigin(recipe, kind: kind); recipeFingerprint(recipe, kind: kind) }
            }
            if historical {
                Text(evolution.practiceJourneyOriginDigest == nil
                     ? "These details and their original reasons remain with the Journey shown above. Connect that Journey again to use them."
                     : "These details belong to the Journey shown above. Their original reasons are retained here; they are not applied to the currently connected Journey.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("evolution-recipe-kept-historical")
            } else if !proposed {
                Text("These are the choices captured when you kept this form. Changing your next direction does not rewrite them.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(recipe.traitExplanations.prefix(5)), id: \.id) { trait in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(trait.title) · \(trait.value)").font(.system(size: 12, weight: .medium))
                        Text(trait.reason).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("evolution-recipe-\(kind)-trait-\(trait.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("evolution-recipe-\(kind)")
    }

    private func recipeOrigin(_ recipe: CompanionAppearanceRecipe, kind: String) -> some View {
        Text("Journey \(recipe.originDigest.prefix(12))")
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            .fixedSize()
            .textSelection(.enabled)
            .accessibilityLabel("Journey origin \(recipe.originDigest)")
            .accessibilityIdentifier("evolution-recipe-\(kind)-origin")
    }

    private func recipeFingerprint(_ recipe: CompanionAppearanceRecipe, kind: String) -> some View {
        Text("Form \(recipe.fingerprint.prefix(12))")
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            .fixedSize()
            .textSelection(.enabled)
            .accessibilityLabel("Form fingerprint \(recipe.fingerprint)")
            .accessibilityIdentifier("evolution-recipe-\(kind)-fingerprint")
    }

    private var knowledge: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("How I help", detail: "Optional preferences for the way ARCHi answers. Confirm, change, or remove them whenever you like.")
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "sparkle.magnifyingglass").foregroundStyle(WorkspaceTheme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("The work we do").font(.system(size: 13, weight: .medium))
                        Picker("Work role", selection: $roleChoice) {
                            Text("Choose a role…").tag(Optional<EvolutionRole>.none)
                            ForEach(EvolutionRole.allCases) { role in Text("\(role.title) · \(role.summary)").tag(Optional(role)) }
                        }.labelsHidden().accessibilityIdentifier("evolution-role")
                        if let role = evolution.confirmedRole { confirmed(role.title, category: .role) }
                    }
                    Button("Confirm") { if let roleChoice { evolution.confirmRole(roleChoice) } }
                        .disabled(roleChoice == nil || roleChoice == evolution.confirmedRole)
                        .accessibilityLabel("Confirm work role")
                }
                Divider()
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "text.bubble").foregroundStyle(WorkspaceTheme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("How help should feel").font(.system(size: 13, weight: .medium))
                        Picker("Help style", selection: $helpChoice) {
                            Text("Choose a style…").tag(Optional<EvolutionHelpStyle>.none)
                            ForEach(EvolutionHelpStyle.allCases) { style in Text(style.title).tag(Optional(style)) }
                        }.labelsHidden().accessibilityIdentifier("evolution-help-style")
                        if let style = evolution.confirmedHelpStyle { confirmed(style.title, category: .helpStyle) }
                    }
                    Button("Confirm") { if let helpChoice { evolution.confirmHelpStyle(helpChoice) } }
                        .disabled(helpChoice == nil || helpChoice == evolution.confirmedHelpStyle)
                        .accessibilityLabel("Confirm help style")
                }
                Text(store.hasPersonalQiMon
                     ? "Your confirmed role and help style guide the next answer. Tone and reply length are set in Personal rhythm. Body changes have their own explicit Keep choice."
                     : "Your confirmed role and help style guide the next answer. Tone and reply length are set in Personal rhythm. Individual body details come from the Journey's origin.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }

    private func confirmed(_ value: String, category: EvolutionPreferenceCategory) -> some View {
        HStack {
            Label("Confirmed · \(value)", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
            Spacer()
            Button("Remove") { evolution.revoke(category) }.buttonStyle(.borderless).font(.system(size: 11))
                .accessibilityLabel("Remove confirmed \(category.rawValue) preference")
        }
    }

    private var families: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Explore a larger appearance change", detail: "These optional local form studies are available whenever you choose. Previewing one leaves the desktop companion unchanged.")
            if let family = evolution.confirmedFamily { confirmed(family.title, category: .family) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(EvolutionFamily.allCases) { family in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { evolution.preview(family) } label: {
                            CompanionPresenceArt(form: shownForm, family: family, size: 128, reduceMotion: true,
                                treatment: store.preferences.visualTreatment, equipment: store.preferences.equipment, seedColor: store.preferences.seedColor)
                                .frame(maxWidth: .infinity).frame(height: 142)
                                .background(Color(red: 0.09, green: 0.13, blue: 0.19), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityLabel("Preview \(family.title)")
                            .accessibilityIdentifier("evolution-preview-\(family.rawValue)")
                        HStack {
                            Text(family.title).font(.system(size: 15, weight: .medium, design: .rounded))
                            Spacer()
                            if evolution.confirmedFamily == family { Image(systemName: "checkmark.circle.fill").foregroundStyle(WorkspaceTheme.accent) }
                        }
                        Text(family.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).frame(minHeight: 48, alignment: .top)
                        Button(evolution.confirmedFamily == family ? "Direction confirmed" : "Use this direction") { evolution.confirmFamily(family); evolution.preview(family) }
                            .buttonStyle(.bordered).controlSize(.small).disabled(evolution.confirmedFamily == family)
                            .accessibilityLabel("Use \(family.title) as visual direction")
                    }.padding(12)
                        .background(WorkspaceTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(evolution.confirmedFamily == family ? WorkspaceTheme.accent.opacity(0.6) : .secondary.opacity(0.15)))
                }
            }
        }
    }

    private var sharedWork: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Work that helped", detail: "After a useful local conversation or shared-document reply, choose This helped my work. Confirm a cited lesson separately when it helped. Feedback counts once per request.")
                HStack {
                    Label("\(evolution.usefulReceipts.count) useful request\(evolution.usefulReceipts.count == 1 ? "" : "s") retained", systemImage: "checkmark.message")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Open assistant") { store.open(.assistant) }.buttonStyle(.borderless)
                }
                DisclosureGroup("Inspect usefulness records", isExpanded: $usefulnessRecordsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        if evolution.usefulReceipts.isEmpty {
                            Text("No work has been marked useful yet.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(evolution.usefulReceipts) { receipt in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Request \(receipt.requestID.uuidString.prefix(8))").font(.system(size: 11, design: .monospaced))
                                    Text(receipt.evidenceTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                    if let source = receipt.sourceDigest {
                                        Text("Source fingerprint \(source.prefix(12))").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    if let binding = receipt.requestBinding {
                                        Text("Input \(binding.inputDigest.prefix(12)) · context \(binding.contextDigest.prefix(12))")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    if let use = receipt.lessonUse {
                                        Text(store.lessonUseDescription(use))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                        Button("Withdraw lesson reference") {
                                            evolution.withdrawLessonUse(requestID: receipt.requestID)
                                        }
                                        .buttonStyle(.borderless).font(.system(size: 11))
                                        .accessibilityLabel("Withdraw lesson reference from request \(receipt.requestID.uuidString.prefix(8))")
                                        .accessibilityIdentifier("evolution-withdraw-lesson-\(receipt.requestID.uuidString)")
                                    }
                                }
                                Spacer()
                                Button("Withdraw") { store.withdrawLearningReview(requestID: receipt.requestID) }.buttonStyle(.borderless)
                                    .accessibilityLabel("Withdraw request \(receipt.requestID.uuidString.prefix(8))")
                                    .accessibilityIdentifier("evolution-withdraw-work-\(receipt.requestID.uuidString)")
                            }
                        }
                    }.padding(.top, 10)
                }
                Text("A lesson reference records your feedback about one answer. Editing or withdrawing a lesson leaves this earlier feedback labeled as history; it never restores that lesson. You can withdraw the reference or the whole work record, then Save evolution.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }

    private var practice: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Practice together", detail: "Keep a completed practice in Journey, then review its reference in Habitat & Arena. Wins, losses, and draws all belong to your history of play.")
                if let origin = evolution.practiceJourneyOriginDigest {
                    DisclosureGroup("Practice origin") {
                        Text("Journey \(origin)")
                            .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("evolution-practice-binding")
                    }
                    Text("Practice records belong to the Journey you connected. Connecting another Journey preserves earlier kept forms and their historical reasons.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Connect a Journey in Habitat & Arena before reviewing one of its outcomes.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Button("Open Habitat & Arena") { store.open(.play) }.buttonStyle(.borderless)
                if evolution.reviewedPractices.isEmpty {
                    Text("No completed practice has been reviewed for this Journey.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(evolution.reviewedPractices) { reference in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(reference.outcome.rawValue.capitalized) · \(reference.rounds) rounds · rules v\(reference.rulesVersion)")
                                .font(.system(size: 12, weight: .medium))
                            Text("Event \(reference.eventId) · \(reference.committedAt)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Button("Withdraw") { evolution.withdrawPractice(id: reference.id) }.buttonStyle(.borderless)
                            .accessibilityLabel("Withdraw practice \(reference.eventId)")
                    }
                }
                if let basis = evolution.keptBasis {
                    DisclosureGroup("Recorded form basis") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(basis.title).font(.system(size: 12, weight: .medium))
                            if let reference = basis.practice {
                                Text("Journey \(reference.originDigest) · event \(reference.eventId)")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Historical reference retained with this form.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var continuity: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Keep your choices. Keep your history.", detail: store.hasPersonalQiMon
                    ? "Your role, help style and development feedback stay in this session until you Save evolution. Kept lessons use their own save controls in Memory."
                    : "Appearance choices and retained records stay in this session until you save. Your documents and conversations stay in their existing places.")
                HStack(spacing: 10) {
                    Button("Save evolution", systemImage: "square.and.arrow.down") { evolution.save() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("evolution-save")
                    Button("Load saved") { if evolution.hasUnsavedChanges { showLoad = true } else { evolution.load() } }.buttonStyle(.bordered)
                    Button("Forget…", role: .destructive) { showForget = true }.buttonStyle(.borderless)
                    Spacer()
                    Text(evolution.requiresReplacement ? "Saved file needs review" : evolution.retentionState.title).font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("evolution-retention-state")
                }
                if evolution.requiresReplacement {
                    Button("Replace saved evolution…", role: .destructive) { showReplace = true }.buttonStyle(.bordered)
                }
                Text(evolution.status).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    .accessibilityIdentifier("evolution-status")
                if !evolution.history.isEmpty {
                    DisclosureGroup("Form history · \(evolution.history.count)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(evolution.history.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(entry.kind == .kept ? "Kept \(entry.family?.title ?? "form")" : "Returned to a starting form",
                                          systemImage: entry.kind == .kept ? "sparkles" : "arrow.uturn.backward")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    if let recipe = entry.appearanceRecipe {
                                        DisclosureGroup("Original appearance details") {
                                            recipeDetails(recipe, proposed: false, identifier: "history-\(entry.id.uuidString)")
                                                .padding(.top, 10)
                                        }
                                    }
                                }
                            }
                        }.padding(.top, 8)
                    }
                }
                Text(store.hasPersonalQiMon
                     ? "Save and Load retain development records for this individual. Identity, lessons and the existing Journey keep their own storage."
                     : "Return to your starter whenever you like. The history of forms you kept remains available here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 17, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }
}

private struct EvolutionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.55))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(WorkspaceTheme.accent.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.28),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}
