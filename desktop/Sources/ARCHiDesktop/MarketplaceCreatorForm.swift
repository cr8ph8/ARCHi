import SwiftUI

/// Bounded recipe editing. The preview remains separate from the worn outfit;
/// collection and equipment changes continue through explicit store actions.
struct MarketplaceCreatorForm: View {
    @Binding var draft: CompanionItemPackage

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    MarketplaceItemPreview(item: draft, size: 98)
                        .frame(width: 108, height: 108)
                        .background(WorkspaceTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        WorkspaceEyebrow(text: "Recipe studio")
                        Text("Make your Focus Staff").font(.system(size: 21, weight: .medium))
                        Text("Shape, color, and a useful little gesture. Your companion stays as they are while you design.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(WorkspaceTheme.line)
                VStack(alignment: .leading, spacing: 12) {
                    WorkspaceEyebrow(text: "Details")
                    LabeledContent("Item name") {
                        TextField("24-character limit", text: $draft.title)
                            .accessibilityIdentifier("marketplace.create.title")
                    }
                    LabeledContent("Creator") {
                        TextField("48-character limit", text: $draft.creator)
                            .accessibilityIdentifier("marketplace.create.creator")
                    }
                    LabeledContent("Description") {
                        TextField("160-character limit", text: $draft.summary, axis: .vertical)
                            .lineLimit(2...3).accessibilityIdentifier("marketplace.create.summary")
                    }
                }
                Divider().overlay(WorkspaceTheme.line)
                VStack(alignment: .leading, spacing: 12) {
                    WorkspaceEyebrow(text: "Appearance & action")
                    Picker("Color", selection: $draft.palette) {
                        ForEach(CompanionItemPackage.Palette.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }.accessibilityIdentifier("marketplace.create.palette")
                    Picker("Crown", selection: $draft.crown) {
                        ForEach(CompanionItemPackage.Crown.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }.accessibilityIdentifier("marketplace.create.crown")
                    Picker("Local action", selection: $draft.action) {
                        Text("Wear only").tag(CompanionItemPackage.Action.decoration)
                        Text("Point to selected passage").tag(CompanionItemPackage.Action.pointSelection)
                    }.accessibilityIdentifier("marketplace.create.action")
                    if draft.action == .pointSelection {
                        Picker("Pace", selection: $draft.defaultGesture.pace) {
                            ForEach(FocusGestureConfiguration.Pace.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Sparkle", selection: $draft.defaultGesture.sparkle) {
                            ForEach(FocusGestureConfiguration.Sparkle.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Hold", selection: $draft.defaultGesture.hold) {
                            ForEach(FocusGestureConfiguration.Hold.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
                Divider().overlay(WorkspaceTheme.line)
                VStack(alignment: .leading, spacing: 12) {
                    WorkspaceEyebrow(text: "Sharing")
                    Picker("Recipe license", selection: $draft.license) {
                        ForEach(CompanionItemPackage.License.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("Design revision \(draft.revision)", value: $draft.revision, in: 1...999)
                    Text("Share recipes you have rights to distribute. Creator names and licenses are declarations.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 12)).textFieldStyle(.roundedBorder)
        }
    }
}
