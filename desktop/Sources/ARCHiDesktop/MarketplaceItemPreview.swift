import SwiftUI

/// The existing equipment renderer places an item beside its companion. Center
/// that same artwork in catalog previews without changing the worn rendering.
struct MarketplaceItemPreview: View {
    let item: CompanionItemPackage
    let size: CGFloat

    var body: some View {
        CompanionEquipmentArt(equipment: .init(hand: .focusStaff, design: item),
            size: size * 1.6, activated: false, reduceMotion: true)
            .offset(x: -size * 0.55, y: -size * 0.02)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
    }
}
