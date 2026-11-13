import SwiftUI

/// A fixed slot keeps row titles aligned regardless of the icon's proportions.
struct ListRowIcon: View {
    let symbol: String
    let color: Color
    var frameSize = AppStyle.Row.listIconFrameSize

    private let glyphSize: CGFloat = 16

    var body: some View {
        Group {
            if let asset = AppAssets.image(named: symbol) {
                Image(platformImage: asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyphSize, height: glyphSize)
            } else if AppIconGlyph.isEmoji(symbol) {
                Text(symbol)
                    .font(.system(size: glyphSize + 1))
            } else {
                Image(systemName: AppIconSymbol.resolved(symbol.isEmpty ? "questionmark" : symbol))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: glyphSize, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}
