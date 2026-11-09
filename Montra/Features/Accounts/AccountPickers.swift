import SwiftUI

/// SF Symbols offered as account icons. A custom asset with the same name wins
/// over the symbol inside `IconTile`, so this list is the one place to add the
/// user's own account artwork later.
enum AccountIconCatalog {
    static let symbols: [String] = [
        "creditcard.fill",
        "banknote.fill",
        "building.columns.fill",
        "wallet.pass.fill",
        "bitcoinsign.circle.fill",
        "dollarsign.circle.fill",
        "eurosign.circle.fill",
        "chart.line.uptrend.xyaxis",
        "bag.fill",
        "gift.fill",
        "briefcase.fill",
        "house.fill",
        "car.fill",
        "airplane",
        "globe.europe.africa.fill",
        "lock.fill",
        "shield.fill",
        "star.fill",
        "heart.fill",
        "pawprint.fill",
        "gamecontroller.fill",
        "graduationcap.fill",
        "tram.fill",
        "fuelpump.fill",
    ]
}

struct IconPicker: View {
    struct Option {
        let symbol: String
        let title: String

        init(_ symbol: String, _ title: String? = nil) {
            self.symbol = symbol
            self.title = title ?? symbol
        }
    }

    @Binding var selection: String
    var options: [Option] = AccountIconCatalog.symbols.map { Option($0) }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: AppStyle.Spacing.xxSmallPlus), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            ForEach(options, id: \.symbol) { option in
                let symbol = option.symbol
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(
                            selection == symbol ? AppColors.surfaceRaised : AppColors.fillSecondary,
                            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                .strokeBorder(selection == symbol ? AppColors.borderStrong : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
    }
}

struct ColorPickerRow: View {
    @Binding var selection: PaletteColor

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.tileColor)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .overlay {
                            if selection == color {
                                Circle()
                                    .inset(by: -3)
                                    .strokeBorder(AppColors.textPrimary, lineWidth: 2)
                            }
                        }
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}
