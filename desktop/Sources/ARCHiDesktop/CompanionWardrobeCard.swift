import SwiftUI

@MainActor
struct CompanionWardrobeCard: View {
    @ObservedObject var store: CompanionStore
    @State private var showsGestureEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkspaceRouteRow(title: store.preferences.equipment.item.map { "Wearing \($0.title)" } ?? "Choose an outfit",
                detail: "Browse, create and manage your items in Marketplace.",
                icon: "bag", identifier: "companion.marketplace") { store.open(.marketplace) }
            DisclosureGroup("Staff gesture", isExpanded: $showsGestureEditor) {
                FocusGestureTeachingCard(store: store).padding(.top, 12)
            }
            .accessibilityIdentifier("companion.staff-gesture")
        }
        .onAppear { if store.focusGestureDraft != nil { showsGestureEditor = true } }
        .onChange(of: store.focusGestureDraft != nil) { _, editing in
            if editing { showsGestureEditor = true }
        }
    }
}
