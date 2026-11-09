import SwiftUI

extension Operation {
    /// Transfers have no category, but they still need a title, glyph and tile.
    var displayTitle: String {
        isTransfer ? String(localized: "transaction.transfer") : (category?.displayName ?? String(localized: "common.uncategorized"))
    }

    var displayIcon: String {
        isTransfer ? "arrow.left.arrow.right" : (category?.iconName ?? "questionmark")
    }

    var displayColor: Color {
        isTransfer ? PaletteColor.sky.tileColor : (category?.color.tileColor ?? AppColors.Chart.neutralTile)
    }
}
