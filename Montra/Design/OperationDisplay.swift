import SwiftUI

extension Operation {
    /// Transfers have no category and use their own title, icon and color.
    var displayTitle: String {
        isTransfer ? String(localized: "transaction.transfer") : (category?.displayName ?? String(localized: "common.uncategorized"))
    }

    var displayIcon: String {
        isTransfer ? "arrow.left.arrow.right" : (category?.iconName ?? "questionmark")
    }

    var displayColor: Color {
        isTransfer ? PaletteColor.sky.tileColor : (category?.color.color ?? AppColors.textTertiary)
    }
}

/// A tinted icon with a fixed slot that keeps titles aligned across rows.
struct TransactionListIcon: View {
    let symbol: String
    let color: Color
    var frameSize = AppStyle.Row.listIconFrameSize

    var body: some View {
        Group {
            if let asset = NSImage(named: symbol) {
                Image(nsImage: asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: AppIconSymbol.resolved(symbol.isEmpty ? "questionmark" : symbol))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}
