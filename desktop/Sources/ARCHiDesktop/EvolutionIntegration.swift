import CryptoKit
import SwiftUI

@MainActor
extension CompanionStore {
    /// Re-read at click time: a previously displayed button cannot admit stale work.
    func evolutionFeedbackReceipt(provider: AssistantProvider, requestID: String) -> AssistantLaneReceipt? {
        guard !isShuttingDown,
              let lane = compareResults[provider], lane.state == .complete,
              !lane.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let receipt = lane.receipt, receipt.state == .complete,
              receipt.provider == provider, receipt.requestID == requestID,
              isCurrent(receipt.context, requireVisible: false) else { return nil }
        if let sourceDigest = receipt.sourceDigest {
            guard sourceName != nil, !sharedText.isEmpty else { return nil }
            let currentDigest = SHA256.hash(data: Data(sharedText.utf8)).map { String(format: "%02x", $0) }.joined()
            guard sourceDigest == currentDigest else { return nil }
        } else {
            // Chat has request evidence, not a fabricated document fingerprint.
            // Also reject direct source mutation that bypassed the context owner.
            guard provider == .qwen, sourceName == nil, sharedText.isEmpty else { return nil }
        }
        guard EvolutionRequestBinding(receipt: receipt).isValid else { return nil }
        return receipt
    }

    @discardableResult
    func markReplyUsefulForEvolution(provider: AssistantProvider, requestID: String) -> Bool {
        guard let receipt = evolutionFeedbackReceipt(provider: provider, requestID: requestID) else { return false }
        let marked = evolution.markUseful(receipt: receipt, sourceDigest: receipt.sourceDigest)
        if marked { recordUsefulReply(requestID: requestID) }
        return marked
    }

    /// A model citation is only a candidate for the user's own usefulness review.
    /// Revalidate the captured lesson so an old button cannot approve a correction
    /// that has since been edited, withdrawn or expired.
    func reviewableEvolutionLessons(provider: AssistantProvider, requestID: String) -> [LessonSnapshot] {
        guard provider == .qwen,
              let receipt = evolutionFeedbackReceipt(provider: provider, requestID: requestID) else { return [] }
        return receipt.localLessons.filter {
            receipt.usedLessonIDs.contains($0.modelID) && currentKeptLesson(matching: $0) != nil
        }
    }

    @discardableResult
    func confirmLessonHelped(provider: AssistantProvider, requestID: String, snapshot: LessonSnapshot) -> Bool {
        guard reviewableEvolutionLessons(provider: provider, requestID: requestID).contains(snapshot),
              let receipt = evolutionFeedbackReceipt(provider: provider, requestID: requestID) else { return false }
        let marked = evolution.markUseful(receipt: receipt, sourceDigest: receipt.sourceDigest, confirmedLesson: snapshot)
        if marked { recordUsefulReply(requestID: requestID) }
        return marked
    }

    func lessonUseDescription(_ use: EvolutionLessonUse) -> String {
        if let kept = keptLessons.first(where: { use.matches(snapshot: LessonSnapshot(lesson: $0)) }) {
            let suffix = currentKeptLesson(matching: LessonSnapshot(lesson: kept)) == nil ? " · expired" : ""
            return "You confirmed “\(kept.topic)” helped · revision \(use.lessonRevision)\(suffix)"
        }
        return "You confirmed an earlier lesson helped · revision \(use.lessonRevision). That version is no longer kept."
    }

    func chooseStartingForm(_ form: CompanionForm) {
        guard canChooseStartingForm, CompanionForm.starterChoices.contains(form) else { return }
        evolution.returnToStarter()
        preferences.form = form
    }

    func returnEvolutionToStarter() {
        guard canChooseStartingForm else { return }
        evolution.returnToStarter()
        preferences.form = evolution.origin
    }
}

/// Both art paths fit the same app-owned frame; a new body never moves its window.
struct CompanionPresenceArt: View {
    let form: CompanionForm
    let family: EvolutionFamily?
    let size: CGFloat
    let reduceMotion: Bool
    var treatment: CompanionVisualTreatment = .original
    var recipe: CompanionAppearanceRecipe? = nil
    var naturalVariation: CompanionNaturalVariation? = nil
    var equipment: CompanionEquipment = .empty
    var lightExpression: KinLightExpression = .resting
    var seedColor: CompanionSeedColor = .original
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var effectiveRecipe: CompanionAppearanceRecipe? {
        guard let family, recipe?.family == family else { return nil }
        return recipe
    }

    private var effectiveNaturalVariation: CompanionNaturalVariation? {
        CompanionVisualAsset.effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation)
    }

    /// Habitat consumes this same drawing instead of maintaining a second body.
    /// Transient light abilities are deliberately absent from the export API.
    @MainActor
    static func png(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment = .original,
                    recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                    equipment: CompanionEquipment = .empty, seedColor: CompanionSeedColor = .original) -> Data? {
        let renderer = ImageRenderer(content: CompanionPresenceArt(form: form, family: family, size: 256, reduceMotion: true,
            treatment: treatment, recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    var body: some View {
        if equipment.isEmpty {
            character
        } else {
            ZStack {
                character
                CompanionEquipmentArt(equipment: equipment, size: size, activated: false,
                    reduceMotion: reduceMotion || systemReduceMotion)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ARCHi, " + CompanionVisualAsset.label(form: form, family: family,
                treatment: treatment, recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor))
        }
    }

    /// Keep the existing body drawing intact when no item is selected. Equipment
    /// occupies the same frame, without becoming part of the individual recipe.
    private var character: some View {
        Group {
            if family == nil, CompanionVisualAsset.tealBody(for: form) != nil {
                // These authored bodies are static studies. Keep native, reduced
                // motion and the hosted PNG exactly on the same frame.
                Group {
                    if let image = CompanionVisualAsset.resolvedImage(form: form, family: family, treatment: treatment) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    } else {
                        CompanionArt(form: form, size: size, reduceMotion: true)
                    }
                }
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("ARCHi, \(form.rawValue) form")
            } else if let image = CompanionVisualAsset.resolvedImage(form: form, family: family, treatment: treatment) {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || systemReduceMotion)) { context in
                    let phase = reduceMotion || systemReduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    if let recipe = effectiveRecipe {
                        personalizedImage(image, recipe: recipe, phase: phase)
                    } else if let variation = effectiveNaturalVariation {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: size, height: size)
                            .modifier(CompanionNaturalFinish(variation: variation))
                            .offset(y: sin(phase * 1.2) * size * 0.018)
                            .accessibilityLabel("ARCHi, " + CompanionVisualAsset.label(form: form, family: family,
                                treatment: treatment, naturalVariation: variation))
                    } else {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: size, height: size)
                            .offset(y: sin(phase * 1.2) * size * 0.018)
                            .accessibilityLabel("ARCHi, \(family?.title ?? form.rawValue) form, \(treatment.rawValue)")
                    }
                }
            } else if let family {
                EvolvedCompanionArt(family: family, size: size, reduceMotion: reduceMotion || systemReduceMotion,
                    recipe: effectiveRecipe, naturalVariation: effectiveNaturalVariation)
            } else {
                CompanionArt(form: form, size: size, reduceMotion: reduceMotion || systemReduceMotion,
                    naturalVariation: effectiveNaturalVariation,
                    lightExpression: [.kinSeed, .kin, .corePearl, .particleSeed, .hamptonSeed].contains(form) ? lightExpression : .resting, treatment: treatment, seedColor: seedColor)
            }
        }.frame(width: size, height: size)
    }

    private func personalizedImage(_ image: NSImage, recipe: CompanionAppearanceRecipe, phase: Double) -> some View {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            // The approved Lumen artwork remains the body. This restrained finish
            // and small core marks are deterministic drawing, never a new raster asset.
            .hueRotation(.degrees((recipe.accentHue - 0.5) * 24))
            .overlay {
                CompanionRecipeMarkings(recipe: recipe, center: CGPoint(x: 0.5, y: 0.594), radius: 0.061)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(x: recipe.horizontalScale, y: 1)
            .offset(y: sin(phase * 1.2 * recipe.motionSpeed) * size * 0.018)
            .accessibilityLabel("ARCHi, \(CompanionVisualAsset.label(form: form, family: family, treatment: treatment, recipe: recipe))")
    }
}

/// Restrained individual variation on existing authored geometry. No role, help
/// preference, or growth milestone participates; motion retains the form's rhythm.
struct CompanionNaturalFinish: ViewModifier {
    let variation: CompanionNaturalVariation

    func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(variation.hueDegrees))
            .overlay {
                Canvas { context, size in
                    let unit = min(size.width, size.height)
                    for index in 0..<variation.markingCount {
                        let angle = variation.markingRotation + Double(index) * 2.1
                        let x = (0.40 + Double(index) * 0.013 + cos(angle) * 0.005) * unit
                        let y = (0.66 + sin(angle) * 0.009 + Double(index % 2) * 0.014) * unit
                        let radius = unit * (0.0055 + Double(index % 2) * 0.001)
                        let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                            width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(ArchiPalette.violet.opacity(0.40)))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(x: variation.horizontalScale, y: 1)
    }
}

/// Small body-local details for the reviewed image-based form.
/// Coordinates are normalized to the existing frame; marks never establish identity.
private struct CompanionRecipeMarkings: View {
    let recipe: CompanionAppearanceRecipe
    let center: CGPoint
    let radius: Double

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let tint = Color(hue: recipe.accentHue, saturation: 0.36, brightness: 0.76)
            for index in 0..<recipe.markingCount {
                let angle = recipe.markingRotation + Double(index) * 2 * .pi / Double(recipe.markingCount)
                let point = CGPoint(x: (center.x + cos(angle) * radius) * unit,
                                    y: (center.y + sin(angle) * radius) * unit)
                let dot = Path(ellipseIn: CGRect(x: point.x - unit * 0.0055, y: point.y - unit * 0.0055,
                                                width: unit * 0.011, height: unit * 0.011))
                context.fill(dot, with: .color(tint.opacity(0.82)))
                context.stroke(dot, with: .color(.white.opacity(0.75)), lineWidth: unit * 0.0025)
            }
        }
    }
}

@MainActor
struct EvolutionReplyFeedback: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider

    var body: some View {
        if let id = store.compareResults[provider]?.receipt?.requestID,
           store.evolutionFeedbackReceipt(provider: provider, requestID: id) != nil {
            let record = store.evolution.usefulReceipts.first { $0.requestID.uuidString == id }
            let lessons = store.reviewableEvolutionLessons(provider: provider, requestID: id)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    store.markReplyUsefulForEvolution(provider: provider, requestID: id)
                } label: {
                    Label(record != nil ? "Usefulness recorded" : "This helped my work", systemImage: record != nil ? "checkmark.circle" : "sparkle")
                }
                .buttonStyle(.borderless).font(.system(size: 11))
                .disabled(record != nil)
                .accessibilityIdentifier("evolution-useful-\(provider.rawValue)")
                .help("Record your usefulness feedback. Retains a request ID and input/context fingerprints, a source fingerprint for shared documents, and an optional confirmed lesson-version reference. No question, document or reply text is copied into Evolution.")

                if provider == .qwen, let use = record?.lessonUse {
                    Text(store.lessonUseDescription(use)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Review in Evolution") { store.open(.evolution) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                } else if !lessons.isEmpty {
                    DisclosureGroup("Did something you taught ARCHi help?") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Qwen cited these lessons. Choose one only if it helped this answer.")
                            ForEach(lessons, id: \.modelID) { lesson in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lesson.topic).fontWeight(.medium)
                                    Text(lesson.text).textSelection(.enabled)
                                    Button("This lesson helped") {
                                        store.confirmLessonHelped(provider: provider, requestID: id, snapshot: lesson)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Confirm lesson \(lesson.topic) helped this answer")
                                    .accessibilityIdentifier("evolution-lesson-helped-\(lesson.modelID)")
                                }
                            }
                            Text("Keeps one lesson reference with this useful request. No lesson text is copied into Evolution. Save evolution to retain it; you can withdraw the reference later.")
                                .foregroundStyle(.secondary)
                        }.padding(.top, 6)
                    }
                    .font(.system(size: 11))
                    .accessibilityIdentifier("evolution-lesson-review")
                }
            }
        }
    }
}
